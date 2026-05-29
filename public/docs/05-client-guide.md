# 5. Client 开发指南

MCP Client 用于连接到 MCP Server，发现并调用 tools、resources、prompts。

```moonbit
// moon.pkg
import { "colmugx/mcp/client" }
```

## 5.1 创建 Client

```moonbit
let client = MCPClient::new(
  name="my-client",
  version="1.0.0",
)
```

## 5.2 Client 结构体

```moonbit
pub struct MCPClient {
  client_name : String                    // Client 名称
  client_version : String                 // Client 版本
  mut transport : AnyTransport?           // 传输层（设置后可用）
  mut server_info : ServerInfo?           // 初始化后的 server 信息
  mut initialized : Bool                  // 是否完成初始化
  mut next_id : Int                       // 下一个请求 ID（自增）
  mut on_tools_changed : (() -> Unit)?    // tools 变更回调
  mut on_resources_changed : (() -> Unit)? // resources 变更回调
  mut on_prompts_changed : (() -> Unit)?  // prompts 变更回调
}
```

## 5.3 生命周期

```
创建 Client → 设置 Transport → initialize() → [使用 API] → close()
```

### 初始化

```moonbit
async fn example {
  let client = MCPClient::new(name="my-client", version="1.0.0")

  // 设置 transport（当前需要手动创建并赋值）
  // client.transport = Some(AnyTransport::Stdio(...))

  // 执行 MCP 初始化握手
  match client.initialize() {
    Ok(_) => println("Connected to server")
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
4. 标记 `initialized = true`

### 关闭连接

```moonbit
client.close()
// 清理 transport、重置 initialized 状态
```

## 5.4 Tool 操作

### 列出 Tools

```moonbit
async fn list_my_tools(client : MCPClient) {
  match client.list_tools() {
    Ok(response_json) => println("Tools: \{response_json}")
    Err(e) => println("Error: \{e.message()}")
  }
}
```

返回值为原始 JSON 字符串，包含 `tools` 数组。

### 调用 Tool

```moonbit
async fn call_my_tool(client : MCPClient) {
  match client.call_tool("get_weather", arguments="{\"city\":\"Tokyo\"}") {
    Ok(response_json) => println("Result: \{response_json}")
    Err(e) => println("Error: \{e.message()}")
  }
}
```

`arguments` 参数为 JSON 字符串格式。

## 5.5 Resource 操作

```moonbit
// 列出 resources
let resources = client.list_resources()

// 读取 resource
let content = client.read_resource("file:///config.json")
```

## 5.6 Prompt 操作

```moonbit
// 列出 prompts
let prompts = client.list_prompts()

// 获取 prompt（带参数）
let result = client.get_prompt(
  "code_review",
  arguments="{\"code\":\"fn main { println(\\\"hi\\\") }\"}",
)
```

## 5.7 其他操作

### Ping

```moonbit
match client.ping() {
  Ok(_) => println("Server is alive")
  Err(e) => println("Ping failed: \{e.message()}")
}
```

### 设置日志级别

```moonbit
client.set_log_level("debug")
```

有效级别：`"debug"`, `"info"`, `"notice"`, `"warning"`, `"error"`, `"critical"`, `"alert"`, `"emergency"`

### 请求 ID 管理

```moonbit
let id1 = client.next_request_id() // 返回 1
let id2 = client.next_request_id() // 返回 2
```

ID 从 1 开始自增，用于 JSON-RPC 请求的 `id` 字段。

## 5.8 通知处理

注册回调以处理 server 发来的变更通知：

```moonbit
client.on_tools_changed(fn() {
  println("Tools list changed! Re-fetching...")
  // 重新调用 client.list_tools()
})

client.on_resources_changed(fn() {
  println("Resources list changed!")
})

client.on_prompts_changed(fn() {
  println("Prompts list changed!")
})
```

当 server 发送 `notifications/tools/list_changed` 等通知时，对应的回调会被触发。

### 手动处理通知

```moonbit
let notification : Notification = ...
handle_server_notification(client, notification)
```

## 5.9 请求构建器参考

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

## 5.10 当前限制

| 功能 | 状态 | 原因 |
|------|------|------|
| `connect_stdio()` | ❌ 未实现 | 需要子进程启动 API |
| `connect_http()` | ❌ 未实现 | `moonbitlang/async` 缺少 HTTP client |
| 响应类型化解析 | ❌ 未实现 | `list_tools` 等返回原始 JSON 字符串 |
| 请求-响应 ID 关联 | 基础实现 | 同步发送/接收，无并发请求 |

这些限制将在后续版本中逐步解决。

## 5.11 完整示例

```moonbit
async fn main {
  // 创建 client
  let client = MCPClient::new(
    name="example-client",
    version="1.0.0",
  )

  // 注册通知回调
  client.on_tools_changed(fn() {
    println("Server tools changed!")
  })

  // 注意：transport 设置需要根据具体场景
  // 当前需要手动创建 transport 并赋值

  // 初始化
  match client.initialize() {
    Ok(_) => {
      println("Initialized!")

      // 列出 tools
      match client.list_tools() {
        Ok(tools_json) => println("Available tools: \{tools_json}")
        Err(e) => println("Failed: \{e.message()}")
      }

      // 调用 tool
      match client.call_tool("hello", arguments="{}") {
        Ok(result) => println("Result: \{result}")
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
