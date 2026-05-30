# 5. Client 开发指南

MCP Client 用于连接到 MCP Server，发现并调用 tools、resources、prompts。

```moonbit
// moon.pkg
import { "colmugx/mcp/client" }
```

## 5.1 创建 Client

```moonbit
let transport = @transport.AnyTransport::HttpClient(
  @transport.HttpClientTransport::new("http://localhost:4240/mcp"),
)
let client = MCPClient::new(
  name="my-client",
  version="1.0.0",
  transport~,
)
```

Transport 在构造时绑定，之后不可更改（数据驱动、组合优于继承）。

## 5.2 Client 结构体

```moonbit
pub struct MCPClient {
  client_name : String                  // Client 名称
  client_version : String               // Client 版本
  transport : @transport.AnyTransport   // 传输层（构造时绑定）
  id_counter : RequestIdCounter         // 请求 ID 生成器（封装自增）
}
```

MCPClient 没有任何 `mut` 字段。`RequestIdCounter` 封装了唯一一个 `mut next_id`，专注于 ID 自增。

## 5.3 生命周期

```
创建 Client（含 transport）→ initialize() → [使用 API] → close()
```

### 初始化

```moonbit
async fn example {
  let transport = @transport.AnyTransport::HttpClient(
    @transport.HttpClientTransport::new("http://localhost:4240/mcp")
  )
  let client = MCPClient::new(name="my-client", version="1.0.0", transport~)

  // 执行 MCP 初始化握手，返回 ServerInfo
  match client.initialize() {
    Ok(server_info) =>
      println("Connected to \{server_info.name} v\{server_info.version}")
    Err(e) => println("Init failed: \{e.message()}")
  }

  // ... 使用 client ...

  client.close()
}
```

`initialize()` 执行以下步骤：
1. 发送 `initialize` 请求（包含 protocolVersion、clientInfo、capabilities）
2. 接收 server 响应（包含 serverInfo、serverCapabilities）
3. 发送 `notifications/initialized` 通知
4. 返回 `ServerInfo`

### 关闭连接

```moonbit
client.close()
// 关闭 transport
```

## 5.4 结果类型

Client API 返回强类型结果，定义在 `client_types.mbt` 中：

```moonbit
pub(all) struct ListToolsResult {
  tools : Array[@types.ToolDefinition]
} derive(Show, Eq)

pub(all) struct CallToolResult {
  content : Array[@types.ContentItem]
  is_error : Bool
} derive(Show, Eq)

pub(all) struct ListResourcesResult {
  resources : Array[@resource.ResourceDefinition]
} derive(Show, Eq)

pub(all) struct ReadResourceResult {
  contents : Array[@resource.ResourceReadResult]
} derive(Show, Eq)

pub(all) struct ListPromptsResult {
  prompts : Array[@prompt.PromptDefinition]
} derive(Show, Eq)
```

## 5.5 Tool 操作

### 列出 Tools

```moonbit
async fn list_my_tools(client : MCPClient) {
  match client.list_tools() {
    Ok(result) => {
      for tool in result.tools {
        println("Tool: \{tool.name} - \{tool.description}")
      }
    }
    Err(e) => println("Error: \{e.message()}")
  }
}
```

返回 `ListToolsResult`，包含 `tools : Array[ToolDefinition]`。

### 调用 Tool

```moonbit
async fn call_my_tool(client : MCPClient) {
  match client.call_tool("get_weather", arguments="{\"city\":\"Tokyo\"}") {
    Ok(result) => {
      if result.is_error {
        println("Tool error!")
      }
      for item in result.content {
        match item {
          Text(text) => println(text)
          _ => ()
        }
      }
    }
    Err(e) => println("Error: \{e.message()}")
  }
}
```

返回 `CallToolResult`，包含 `content : Array[ContentItem]` 和 `is_error : Bool`。`arguments` 参数为 JSON 字符串格式。

## 5.6 Resource 操作

```moonbit
// 列出 resources — 返回 ListResourcesResult
async fn list_my_resources(client : MCPClient) {
  match client.list_resources() {
    Ok(result) => {
      for res in result.resources {
        println("Resource: \{res.name} (\{res.uri})")
      }
    }
    Err(e) => println("Error: \{e.message()}")
  }
}

// 读取 resource — 返回 ReadResourceResult
async fn read_my_resource(client : MCPClient) {
  match client.read_resource("file:///config.json") {
    Ok(result) => {
      for item in result.contents {
        match item.content {
          Text(text) => println("\{item.uri}: \{text}")
          Blob(data, mime_type~) => println("\{item.uri}: [binary \{mime_type}]")
        }
      }
    }
    Err(e) => println("Error: \{e.message()}")
  }
}
```

## 5.7 Prompt 操作

```moonbit
// 列出 prompts — 返回 ListPromptsResult
async fn list_my_prompts(client : MCPClient) {
  match client.list_prompts() {
    Ok(result) => {
      for prompt in result.prompts {
        println("Prompt: \{prompt.name}")
      }
    }
    Err(e) => println("Error: \{e.message()}")
  }
}

// 获取 prompt（带参数）— 返回 GetPromptResult
async fn get_my_prompt(client : MCPClient) {
  match client.get_prompt(
    "code_review",
    arguments="{\"code\":\"fn main { println(\\\"hi\\\") }\"}",
  ) {
    Ok(result) => {
      for msg in result.messages {
        match msg.content {
          Text(text) => println("[\{msg.role}] \{text}")
          _ => ()
        }
      }
    }
    Err(e) => println("Error: \{e.message()}")
  }
}
```

## 5.8 其他操作

### Ping

```moonbit
match client.ping() {
  Ok(_) => println("Server is alive")
  Err(e) => println("Ping failed: \{e.message()}")
}
```

### 设置日志级别

```moonbit
match client.set_log_level("debug") {
  Ok(_) => println("Log level set")
  Err(e) => println("Failed: \{e.message()}")
}
```

有效级别：`"debug"`, `"info"`, `"notice"`, `"warning"`, `"error"`, `"critical"`, `"alert"`, `"emergency"`

### 请求 ID 管理

```moonbit
let id1 = client.next_request_id() // 返回 1
let id2 = client.next_request_id() // 返回 2
```

ID 从 1 开始自增，用于 JSON-RPC 请求的 `id` 字段。内部通过 `RequestIdCounter` 封装。

## 5.9 通知处理

使用 `NotificationHandlers` 结构体处理 server 发来的变更通知（数据驱动模式）：

```moonbit
let handlers : NotificationHandlers = {
  on_tools_changed: Some(fn() {
    println("Tools list changed! Re-fetching...")
    // 重新调用 client.list_tools()
  }),
  on_resources_changed: Some(fn() {
    println("Resources list changed!")
  }),
  on_prompts_changed: None,
}

// 收到通知时手动分发
let notification : @types.Notification = ...
handle_server_notification(handlers, notification)
```

`NotificationHandlers` 是一个纯数据结构，没有 `mut`，通过 `handle_server_notification` 函数进行模式匹配分发。

## 5.10 请求构建器参考

所有 JSON-RPC 请求构建函数在 `request_builder.mbt` 中：

| 函数 | 说明 |
|------|------|
| `build_initialize_request(id, name, version)` | 初始化请求 |
| `build_initialized_notification()` | 初始化完成通知 |
| `build_ping_request(id)` | Ping 请求 |
| `build_tools_list_request(id)` | 列出工具 |
| `build_tools_call_request(id, name, arguments?)` | 调用工具 |
| `build_resources_list_request(id)` | 列出资源 |
| `build_resources_read_request(id, uri)` | 读取资源 |
| `build_prompts_list_request(id)` | 列出提示 |
| `build_prompts_get_request(id, name, arguments?)` | 获取提示 |
| `build_set_log_level_request(id, level)` | 设置日志级别 |

这些函数返回格式化的 JSON-RPC 请求字符串，可以在自定义场景中使用：

```moonbit
let req = build_tools_call_request(1, "my_tool", arguments="{\"x\":42}")
// req = {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"my_tool","arguments":{"x":42}}}
```

## 5.11 当前限制

| 功能 | 状态 | 原因 |
|------|------|------|
| 请求-响应 ID 关联 | 基础实现 | 同步发送/接收，无并发请求 |

这些限制将在后续版本中逐步解决。

## 5.12 完整示例

```moonbit
async fn main {
  // 创建 client（transport 在构造时绑定）
  let transport = @transport.AnyTransport::HttpClient(
    @transport.HttpClientTransport::new("http://localhost:4240/mcp"),
  )
  let client = MCPClient::new(
    name="example-client",
    version="1.0.0",
    transport~,
  )

  // 初始化（返回 ServerInfo）
  match client.initialize() {
    Ok(server_info) => {
      println("Connected to \{server_info.name} v\{server_info.version}")

      // 列出 tools（强类型返回）
      match client.list_tools() {
        Ok(result) => {
          for tool in result.tools {
            println("Tool: \{tool.name}")
          }
        }
        Err(e) => println("Failed: \{e.message()}")
      }

      // 调用 tool（强类型返回）
      match client.call_tool("hello", arguments="{}") {
        Ok(result) => {
          for item in result.content {
            match item {
              Text(text) => println("Result: \{text}")
              _ => ()
            }
          }
        }
        Err(e) => println("Error: \{e.message()}")
      }

      // Ping
      ignore(client.ping())
    }
    Err(e) => println("Init failed: \{e.message()}")
  }

  client.close()
}
```
