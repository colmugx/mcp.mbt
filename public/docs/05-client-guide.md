# 5. Client 开发指南

MCP Client 用于连接到 MCP Server，发现并调用 tools、resources、prompts。支持双向通信（server→client 请求）和 MCP 2025-11-25 规范。

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

Transport 在构造时绑定，之后不可更改。可通过 `capabilities?` 参数自定义客户端能力（默认启用 roots、sampling、elicitation）。

## 5.2 Client 结构体

```moonbit
pub struct MCPClient {
  client_name : String                  // Client 名称
  client_version : String               // Client 版本
  capabilities : ClientCapabilities     // 客户端能力声明
  transport : @transport.AnyTransport   // 传输层（构造时绑定）
  id_counter : RequestIdCounter         // 请求 ID 生成器
  server_capabilities : ServerCapabilities?  // 服务器能力（initialize 后填充）
  notification_handlers : NotificationHandlers  // 通知处理器
  sampling_handler : ((Json) -> Result[CreateMessageResult, MCPError])?   // sampling 请求处理
  roots_handler : (() -> Result[Array[Root], MCPError])?                  // roots 请求处理
  elicitation_handler : ((Json) -> Result[ElicitationResult, MCPError])?  // elicitation 请求处理
  response_map : Map[Int, @aqueue.Queue[String]]  // 双向模式下的响应队列
  mut event_loop_started : Bool         // 是否已进入事件循环模式
}
```

核心设计：结构体以不可变为主，仅 `event_loop_started` 为 `mut`。Handler 注册通过 builder pattern 返回新实例。

## 5.3 生命周期

### 单向模式（legacy）

```
创建 Client → initialize() → [使用 API] → close()
```

适用于简单的请求-响应场景。

### 双向模式（bidirectional）

```
创建 Client → 注册 handlers → run(group) → [事件循环自动运行]
```

适用于需要处理 server 主动请求（sampling、roots、elicitation）和通知的场景。`run()` 内部自动执行 `initialize()`，然后进入事件循环。

## 5.4 结果类型

Client API 返回强类型结果。所有列表结果支持分页（`next_cursor`）：

```moonbit
pub(all) struct ListToolsResult {
  tools : Array[@types.ToolDefinition]
  next_cursor : String?    // 分页游标，None 表示最后一页
} derive(Show, Eq)

pub(all) struct ListResourcesResult {
  resources : Array[@resource.ResourceDefinition]
  next_cursor : String?
} derive(Show, Eq)

pub(all) struct ListPromptsResult {
  prompts : Array[@prompt.PromptDefinition]
  next_cursor : String?
} derive(Show, Eq)

pub(all) struct ListResourceTemplatesResult {
  resource_templates : Array[ResourceTemplate]
  next_cursor : String?
} derive(Show, Eq)

pub(all) struct CallToolResult {
  content : Array[@types.ContentItem]
  is_error : Bool
} derive(Show, Eq)

pub(all) struct ReadResourceResult {
  contents : Array[@resource.ResourceReadResult]
} derive(Show, Eq)

pub(all) struct CompletionResult {
  values : Array[String]
  total : Int?
  has_more : Bool?
} derive(Show, Eq)

pub(all) struct ResourceTemplate {
  uri_template : String    // URI 模板（如 "file:///{path}"）
  name : String
  description : String?
  mime_type : String?
} derive(Show, Eq)
```

## 5.5 Tool 操作

### 列出 Tools（支持分页）

```moonbit
async fn list_all_tools(client : MCPClient) {
  var cursor = ""
  var all_tools = []
  while true {
    match client.list_tools(cursor~) {
      Ok(result) => {
        all_tools = all_tools + result.tools
        match result.next_cursor {
          Some(c) => cursor = c
          None => break
        }
      }
      Err(e) => println("Error: \{e.message()}"); break
    }
  }
}
```

### 调用 Tool

```moonbit
async fn call_my_tool(client : MCPClient) {
  match client.call_tool("get_weather", arguments="{\"city\":\"Tokyo\"}") {
    Ok(result) => {
      if result.is_error { println("Tool error!") }
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

## 5.6 Resource 操作

```moonbit
// 列出 resources（支持分页）
match client.list_resources(cursor~) {
  Ok(result) => // result.resources, result.next_cursor
  Err(e) => ...
}

// 读取 resource
match client.read_resource("file:///config.json") {
  Ok(result) => // result.contents (Array[ResourceReadResult])
  Err(e) => ...
}

// 订阅 resource 变更
match client.subscribe_resource("file:///config.json") {
  Ok(_) => println("Subscribed")
  Err(e) => ...
}

// 取消订阅
match client.unsubscribe_resource("file:///config.json") {
  Ok(_) => println("Unsubscribed")
  Err(e) => ...
}

// 列出 resource templates（支持分页）
match client.list_resource_templates(cursor~) {
  Ok(result) => // result.resource_templates, result.next_cursor
  Err(e) => ...
}
```

## 5.7 Prompt 操作

```moonbit
// 列出 prompts（支持分页）
match client.list_prompts(cursor~) {
  Ok(result) => // result.prompts, result.next_cursor
  Err(e) => ...
}

// 获取 prompt（带参数）
match client.get_prompt("code_review", arguments="{\"code\":\"fn main { }\"}") {
  Ok(result) => // result.description?, result.messages
  Err(e) => ...
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

### Completion（参数补全）

```moonbit
match client.complete(
  ref_type~="ref/prompt",
  ref_name~="code_review",
  argument_name~="language",
  argument_value~="py",
) {
  Ok(result) => {
    // result.values: Array[String] — 补全建议
    // result.total: Int? — 总数
    // result.has_more: Bool? — 是否还有更多
  }
  Err(e) => ...
}
```

`ref_type` 可选值：`"ref/prompt"` 或 `"ref/resource"`。

### 请求 ID 管理

```moonbit
let id1 = client.next_request_id() // 返回 1
let id2 = client.next_request_id() // 返回 2
```

ID 从 1 开始自增，内部通过 `RequestIdCounter` 封装。

## 5.9 通知处理

使用 `NotificationHandlers` 结构体处理 server 发来的通知。支持 7 种通知类型：

```moonbit
pub(all) struct NotificationHandlers {
  on_tools_changed : (() -> Unit)?
  on_resources_changed : (() -> Unit)?
  on_prompts_changed : (() -> Unit)?
  on_progress : ((ProgressNotification) -> Unit)?
  on_cancelled : ((CancelledNotification) -> Unit)?
  on_resource_updated : ((ResourceUpdatedNotification) -> Unit)?
  on_message : ((String, Json?) -> Unit)?   // 未识别通知的 fallback
}
```

### 使用方式

```moonbit
let handlers : NotificationHandlers = {
  ..NotificationHandlers::empty(),
  on_tools_changed: Some(fn() {
    println("Tools list changed! Re-fetching...")
  }),
  on_progress: Some(fn(n) {
    println("Progress: \{n.progress} / \{n.total}")
  }),
  on_resource_updated: Some(fn(n) {
    println("Resource updated: \{n.uri}")
  }),
}

// 手动分发
handle_server_notification(handlers, notification)
```

`NotificationHandlers` 是纯数据结构，通过 `handle_server_notification` 函数进行模式匹配分发。

### 通知类型详情

| 通知方法 | Handler 类型 | 说明 |
|----------|-------------|------|
| `notifications/tools/list_changed` | `() -> Unit` | 工具列表变更 |
| `notifications/resources/list_changed` | `() -> Unit` | 资源列表变更 |
| `notifications/prompts/list_changed` | `() -> Unit` | 提示列表变更 |
| `notifications/progress` | `(ProgressNotification) -> Unit` | 进度通知（token, progress, total?） |
| `notifications/cancelled` | `(CancelledNotification) -> Unit` | 请求取消（request_id, reason?） |
| `notifications/resources/updated` | `(ResourceUpdatedNotification) -> Unit` | 资源内容变更（uri） |
| 其他 | `(String, Json?) -> Unit` | fallback，接收方法名和参数 |

## 5.10 双向通信（Bidirectional）

Client 可以处理 server 主动发起的请求。通过 builder pattern 注册 handler 并启动事件循环：

### 注册 Handler

```moonbit
let client = MCPClient::new(name="my-client", version="1.0.0", transport~)
  .on_sampling(fn(params) {
    // 处理 sampling/createMessage 请求
    Ok({
      role: "assistant",
      model: "my-model",
      content: ContentItem::Text("response"),
      stop_reason: Some("endTurn"),
    })
  })
  .on_roots(fn() {
    // 处理 roots/list 请求
    Ok([{ uri: "file:///home/user/project", name: Some("project") }])
  })
  .on_elicitation(fn(params) {
    // 处理 elicitation/create 请求
    Ok({ action: "accept", content: Some(@json.object({ "answer": @json.string("yes") })) })
  })
  .on_notification({
    ..NotificationHandlers::empty(),
    on_progress: Some(fn(n) { println("Progress: \{n.progress}") }),
  })
```

### 运行事件循环

```moonbit
@async.with_task_group(fn(group) {
  client.run(group)
  // run() 自动执行:
  // 1. initialize() 握手
  // 2. 进入事件循环，接收消息并分发:
  //    - method + id → server 请求 → 调用对应 handler → send(response)
  //    - method (no id) → server 通知 → handle_server_notification()
  //    - id (no method) → server 响应 → 唤醒等待的 send_request()
  // 3. transport 关闭时退出
})
```

### 事件循环下的请求模式

进入 `run()` 后，`send_request` 自动切换为异步队列模式：

```
send_request() → 注册 pending queue → transport.send() → queue.get() 等待
                                                        ↑
                          事件循环收到 response → dispatch_response() → queue.put()
```

## 5.11 请求构建器参考

所有 JSON-RPC 请求构建函数在 `request_builder.mbt` 中：

| 函数 | 说明 |
|------|------|
| `build_initialize_request(id, name, version, capabilities~)` | 初始化请求（含客户端能力） |
| `build_initialized_notification()` | 初始化完成通知 |
| `build_ping_request(id)` | Ping 请求 |
| `build_tools_list_request(id, cursor?)` | 列出工具（支持分页） |
| `build_tools_call_request(id, name, arguments?, progress_token?)` | 调用工具（含进度 token） |
| `build_resources_list_request(id, cursor?)` | 列出资源（支持分页） |
| `build_resources_read_request(id, uri)` | 读取资源 |
| `build_resources_subscribe_request(id, uri)` | 订阅资源变更 |
| `build_resources_unsubscribe_request(id, uri)` | 取消订阅资源 |
| `build_resources_templates_list_request(id, cursor?)` | 列出资源模板（支持分页） |
| `build_prompts_list_request(id, cursor?)` | 列出提示（支持分页） |
| `build_prompts_get_request(id, name, arguments?)` | 获取提示 |
| `build_set_log_level_request(id, level)` | 设置日志级别 |
| `build_completion_complete_request(id, ref_type~, ref_name~, argument_name~, argument_value~)` | 参数补全 |

这些函数返回格式化的 JSON-RPC 请求字符串。

## 5.12 完整示例

### 单向模式

```moonbit
async fn main {
  let transport = @transport.AnyTransport::HttpClient(
    @transport.HttpClientTransport::new("http://localhost:4240/mcp"),
  )
  let client = MCPClient::new(name="example-client", version="1.0.0", transport~)

  match client.initialize() {
    Ok(server_info) => {
      println("Connected to \{server_info.name} v\{server_info.version}")
      match client.list_tools() {
        Ok(result) => {
          for tool in result.tools {
            println("Tool: \{tool.name}")
          }
        }
        Err(e) => println("Failed: \{e.message()}")
      }
      ignore(client.ping())
    }
    Err(e) => println("Init failed: \{e.message()}")
  }

  client.close()
}
```

### 双向模式

```moonbit
fn main {
  let transport = @transport.AnyTransport::HttpClient(
    @transport.HttpClientTransport::new("http://localhost:4240/mcp"),
  )
  let client = MCPClient::new(name="bidirectional-client", version="1.0.0", transport~)
    .on_roots(fn() {
      Ok([{ uri: "file:///workspace", name: Some("workspace") }])
    })
    .on_notification({
      ..NotificationHandlers::empty(),
      on_tools_changed: Some(fn() { println("Tools changed!") }),
    })

  @async.with_task_group(fn(group) {
    // run() 自动初始化并进入事件循环
    // 可在 group 上 spawn 其他任务发送请求
    client.run(group)
  })
}
```
