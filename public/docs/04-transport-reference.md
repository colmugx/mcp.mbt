# 4. Transport 参考手册

Transport 层定义在 `colmugx/mcp/transport` 包中。

```moonbit
// moon.pkg
import { "colmugx/mcp/transport" }
```

## 4.1 Transport Trait

```moonbit
pub(open) trait Transport {
  receive(Self) -> String? raise @types.TransportError
  send(Self, String) -> Unit raise @types.TransportError
  send_notification(Self, @types.Notification) -> Unit raise @types.TransportError
  send_event(Self, event_type~ : String, data~ : String) -> Unit
  supports_streaming(Self) -> Bool
  close(Self) -> Unit
}
```

| 方法 | 说明 |
|------|------|
| `receive()` | 接收一条 JSON-RPC 消息。返回 `None` 表示连接关闭。 |
| `send(msg)` | 发送 JSON-RPC 响应。会验证消息格式。 |
| `send_notification(notification)` | 发送 MCP 通知。 |
| `send_event(event_type, data)` | 发送 SSE 事件（仅 HTTP transport 有效）。 |
| `supports_streaming()` | 是否支持 SSE 流式推送。 |
| `close()` | 关闭传输连接。 |

## 4.2 AnyTransport 枚举

```moonbit
pub(all) enum AnyTransport {
  Stdio(StdioTransport)
  Http(HttpTransport)
  HttpClient(HttpClientTransport)
}
```

`AnyTransport` 为所有方法提供了分发实现，可以直接调用而无需 match：

```moonbit
let transport : AnyTransport = ...
transport.send(response)        // 自动分发到具体实现
transport.receive()             // 同上
transport.close()
```

## 4.3 StdioTransport

通过标准输入/输出通信，适用于子进程模式。

```moonbit
let transport = StdioTransport::new()
```

| 特性 | 说明 |
|------|------|
| `receive()` | 从 stdin 按行读取 JSON-RPC 消息 |
| `send()` | 写入 stdout（带 8KB 缓冲） |
| `supports_streaming()` | 返回 `false` |
| 性能优化 | 使用 BufferedWriter 减少系统调用 |

典型用法 — MCP server 由 host 启动为子进程：

```moonbit
async fn main {
  let server = mcp_server(name="my-server", version="1.0.0")
  server.run_stdio() // 内部创建 StdioTransport
}
```

## 4.4 HttpTransport（Server 端）

HTTP server 端 transport，实现 Streamable HTTP 传输协议。

```moonbit
let transport = HttpTransport::new(
  port=4240,                    // 监听端口，默认 4240
  endpoint_path="/mcp",         // 端点路径，默认 "/mcp"
)
```

| 特性 | 说明 |
|------|------|
| `POST /mcp` | 接收 JSON-RPC 请求 |
| `GET /mcp` | SSE 通知流（server → client 推送） |
| `supports_streaming()` | 返回 `true` |
| `start()` | 启动 HTTP server（阻塞运行） |

典型用法：

```moonbit
async fn main {
  @async.with_task_group(fn(group) {
    let server = mcp_server(name="my-server", version="1.0.0")
    server.run_http(port=8080, path="/mcp", group~)
  })
}
```

`run_http` 内部：
1. 创建 `HttpTransport`
2. 在 TaskGroup 中启动 `http.start()` 作为后台任务
3. 调用 `server.run(transport, group)` 进入请求处理循环

## 4.5 HttpClientTransport（Client 端）

HTTP client 端 transport，用于连接到远程 MCP server。实现 Streamable HTTP 传输协议：POST 用于请求-响应，GET SSE 用于 server→client 通知。

```moonbit
let transport = HttpClientTransport::new("http://localhost:4240/mcp")
```

### 结构体

```moonbit
pub struct HttpClientTransport {
  base_url : String            // MCP server 的 HTTP 端点 URL
  mut session_id : String?     // 会话 ID（从 server 响应头中获取）
  mut last_response : String?  // 上次 POST 响应缓存
  mut last_response_status : Int
  mut sse_client : @http.Client?  // SSE 流式连接
  mut sse_connected : Bool
  mut closed : Bool
}
```

### 工作流程

1. **首次 `send()`** 时自动建立 SSE 连接（lazy SSE establishment）
2. `send()` 通过 `POST` 发送 JSON-RPC 请求，自动携带 `Mcp-Session-Id` 和 `Content-Type` 头
3. `receive()` 优先返回上次 POST 的响应，否则从 SSE 流读取
4. Server 响应头中的 `mcp-session-id` 会被自动提取并用于后续请求

| 特性 | 说明 |
|------|------|
| `send()` | POST JSON-RPC 请求，自动管理 session 和 SSE |
| `receive()` | 返回 POST 响应或 SSE 事件 |
| `send_notification()` | POST 通知（无 id，fire-and-forget） |
| `supports_streaming()` | 返回 `true` |
| 会话管理 | 自动从响应头获取 `Mcp-Session-Id` |
| SSE | lazy 建立，自动解析 `data:` 行 |

### 使用示例

```moonbit
async fn main {
  let transport = AnyTransport::HttpClient(
    HttpClientTransport::new("http://localhost:4240/mcp"),
  )
  let client = MCPClient::new(
    name="my-client",
    version="1.0.0",
    transport~,
  )

  match client.initialize() {
    Ok(server_info) => {
      println("Connected to \{server_info.name}")
      // 使用 client API
      match client.list_tools() {
        Ok(tools) => println("Tools: \{tools}")
        Err(e) => println("Error: \{e.message()}")
      }
    }
    Err(e) => println("Init failed: \{e.message()}")
  }
  client.close()
}
```

## 4.6 消息验证

```moonbit
pub fn validate_jsonrpc_message(message : String) -> Result[Unit, MCPError]
```

验证一个字符串是否为合法的 JSON-RPC 2.0 消息（必须包含 `jsonrpc: "2.0"` 和 `method`/`result`/`error` 之一）。`StdioTransport::send()` 内部自动调用此函数验证发出的消息。

## 4.7 自定义 Transport

实现 `Transport` trait 可以创建自定义传输层：

```moonbit
struct MyTransport {
  // 自定义字段
}

impl Transport for MyTransport with receive(self) -> String? raise @types.TransportError {
  // 从自定义源读取消息
  Some("...")
}

impl Transport for MyTransport with send(self, msg : String) -> Unit raise @types.TransportError {
  // 发送消息到自定义目标
}

impl Transport for MyTransport with send_notification(self, n : @types.Notification) -> Unit raise @types.TransportError {
  let json = @jsonutil.jsonrpc_notification(n.method_name, n.params)
  self.send(json)
}

impl Transport for MyTransport with send_event(self, event_type~ : String, data~ : String) -> Unit {
  // 可选：SSE 事件推送
}

impl Transport for MyTransport with supports_streaming(self) -> Bool {
  false
}

impl Transport for MyTransport with close(self) -> Unit {
  // 清理资源
}
```

使用时包装到 `AnyTransport` 或直接传递给 `MCPServer::run()`。

## 4.8 跨平台支持

Transport 包通过 MoonBit 的 `targets` 机制支持条件编译：

| 文件 | native | wasm-gc |
|------|--------|---------|
| `transport.mbt` | ✅ | ✅ |
| `stdio.mbt` | ✅ | — |
| `http_server.mbt` | ✅ | — |
| `http_client.mbt` | ✅ | — |
| `http_compliance_test.mbt` | ✅ | — |
| `unimplemented.mbt` | — | ✅（stub） |

在 wasm-gc 上，`StdioTransport::new()` 和 `HttpTransport::new()` 会 abort。`Transport` trait 和 `AnyTransport` 类型定义在 wasm-gc 上可用，但无法实际进行 I/O。
