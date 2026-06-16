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
  StdioClient(StdioClientTransport)
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

### 服务器端认证

通过 `AuthConfig` 配置 Bearer token 验证和 Protected Resource Metadata：

```moonbit
let transport = HttpTransport::new(port=4240)
  .with_auth(AuthConfig::new(
    verify_token=fn(token) {
      // 验证 token 是否有效
      token == "my-secret-token"
    },
    resource_metadata_url="http://localhost:4240/mcp",
    authorization_servers=["https://auth.example.com"],
    required_scopes="mcp:read",
    allowed_origins=["http://localhost:3000"],
  ))
```

或通过 Server builder API：

```moonbit
let server = mcp_server(name="my-server", version="1.0.0")
  .with_auth(AuthConfig::new(
    verify_token=fn(token) { validate(token) },
    resource_metadata_url="http://localhost:4240/mcp",
    authorization_servers=["https://auth.example.com"],
  ))
  .run_http(port=4240, group~)
```

#### AuthConfig 字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `verify_token` | `(String) -> Bool` | 验证 Bearer token，返回 true 表示有效 |
| `resource_metadata_url` | `String` | 资源 URL，用于 WWW-Authenticate 头和元数据 |
| `authorization_servers` | `Array[String]` | 授权服务器 URL 列表（RFC 9728） |
| `required_scopes` | `String?` | 所需权限范围（如 `"mcp:read mcp:write"`） |
| `allowed_origins` | `Array[String]?` | 允许的 Origin（DNS rebinding 防护） |

#### 认证行为

- 每个请求到达时，提取 `Authorization` 头验证 token
- 无 token 或无效 token → 返回 `401 Unauthorized` + `WWW-Authenticate` 头
- `allowed_origins` 配置时，验证 `Origin` 头防止 DNS rebinding 攻击
- 自动提供 `/.well-known/oauth-protected-resource` 端点（RFC 9728）

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

Server 运行时会按 transport 类型选择响应路径：
- `stdio` 共享一个串行发送队列，避免 stdout 交错
- `http` 为每个 POST 请求保留独立 reply queue，response 直接写回对应连接

## 4.5 HttpClientTransport（Client 端）

HTTP client 端 transport，用于连接到远程 MCP server。实现 Streamable HTTP 传输协议（MCP 2025-11-25）：POST 用于请求-响应，GET SSE 用于 server→client 通知。

```moonbit
let transport = HttpClientTransport::new("http://localhost:4240/mcp")
```

### 客户端认证

在构造时传入 `auth_token` 参数，自动在所有请求中携带 `Authorization: Bearer <token>` 头：

```moonbit
let transport = HttpClientTransport::new(
  "http://localhost:4240/mcp",
  auth_token="my-secret-token",
)
```

认证行为：
- `Authorization: Bearer <token>` 自动注入到所有 HTTP 请求（POST、GET SSE、DELETE）
- HTTP 401 响应 → 抛出 `TransportError::Unauthorized`（包含 `WWW-Authenticate` 信息）
- HTTP 403 响应 → 抛出 `TransportError::Forbidden`

### 结构体

```moonbit
pub struct HttpClientTransport {
  base_url : String                // MCP server 的 HTTP 端点 URL
  mut session_id : String?         // 会话 ID（从 server 响应头获取）
  mut last_response : String?      // 上次 POST 的 JSON 响应缓存
  mut last_response_status : Int   // 上次响应的 HTTP 状态码
  mut last_event_id : String?      // 上次 SSE 事件的 ID（用于断线重连）
  mut sse_pending_responses : Array[String]?  // POST SSE 响应中累积的事件
  mut sse_pending_index : Int      // SSE 事件的 FIFO 读取索引
  protocol_version : String        // MCP 协议版本（"2025-11-25"）
  mut sse_client : @http.Client?   // SSE GET 流式连接
  mut sse_connected : Bool
  mut closed : Bool
}
```

### 工作流程

1. **`send()`** 通过 `@http.post_stream()` 发送 JSON-RPC 请求，携带以下头：
   - `Content-Type: application/json`
   - `Accept: application/json, text/event-stream`
   - `MCP-Protocol-Version: 2025-11-25`
   - `Mcp-Session-Id`（如果已获取）
2. 响应处理：
   - **HTTP 404** → 抛出 `InvalidState("session expired, re-initialize")`
   - **`application/json`** → 缓存到 `last_response`
   - **`text/event-stream`** → 解析 SSE 事件，累积到 `sse_pending_responses`，提取 `id:` 存入 `last_event_id`
3. **`receive()`** 按 FIFO 顺序返回：SSE pending → last_response → SSE GET 通道
4. Server 响应头中的 `mcp-session-id` 被自动提取并用于后续请求
5. **`send_notification()`** 使用 `post_stream` 发送通知，读取并丢弃响应

| 特性 | 说明 |
|------|------|
| `send()` | POST JSON-RPC 请求，支持 SSE 流式响应 |
| `receive()` | FIFO 返回 SSE pending → POST response → SSE GET |
| `send_notification()` | POST 通知（fire-and-forget） |
| `close_session()` | 发送 HTTP DELETE 终止会话，然后 close() |
| `supports_streaming()` | 返回 `true` |
| 会话管理 | 自动获取 `Mcp-Session-Id`，支持 DELETE 终止 |
| SSE | lazy 建立 GET 流，支持 `Last-Event-ID` 断线重连 |
| 协议版本 | 所有请求携带 `MCP-Protocol-Version: 2025-11-25` |

### 关闭会话

```moonbit
// 优雅关闭：发送 HTTP DELETE 通知 server 终止会话
transport.close_session()  // 仅在 HttpClientTransport 上可用
// 或
client.close()  // 仅关闭 transport 连接，不发送 DELETE
```

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

## 4.6 StdioClientTransport（Client/Host 端）

Stdio client 端 transport，用于 MCP host 连接本地 MCP server。按照 MCP 规范：host 启动 server 作为子进程，通过 stdin/stdout 管道进行 JSON-RPC 通信。

**与 `StdioTransport` 的区别：**
- `StdioTransport`：Server 端，绑定当前进程的 stdin/stdout
- `StdioClientTransport`：Client/Host 端，spawn 子进程并 pipe 其 stdin/stdout

### 两阶段初始化

```moonbit
// 1. 创建 transport（仅存储配置，不启动进程）
let transport = StdioClientTransport::new(
  cmd="moon",
  args=["run", "path/to/server"],
)
// 2. 在 TaskGroup 中启动子进程
transport.start(group)
```

### 结构体

```moonbit
pub struct StdioClientTransport {
  cmd : String              // 子进程命令
  args : Array[String]      // 子进程参数
  extra_env : Map[String, String]  // 额外环境变量
  mut closed : Bool
  mut reader : @process.ReadFromProcess?   // 子进程 stdout 管道
  mut raw_writer : @process.WriteToProcess?  // 子进程 stdin 管道
  mut writer : @io.BufferedWriter[@process.WriteToProcess]?  // 带缓冲的写入器
}
```

### 方法

| 方法 | 说明 |
|------|------|
| `new(cmd, args, extra_env?)` | 创建 transport，存储配置（不启动进程） |
| `start(group)` | 在 TaskGroup 中 spawn 子进程，创建 pipe |
| `receive()` | 从子进程 stdout 读取 JSON-RPC 消息 |
| `send(message)` | 向子进程 stdin 写入 JSON-RPC 消息（带缓冲 + flush） |
| `send_notification(notification)` | 发送通知到子进程 stdin |
| `supports_streaming()` | 返回 `false` |
| `close()` | 优雅关闭（关闭 stdin → 信号 EOF → 关闭 stdout） |

### 优雅关闭流程（符合 MCP 规范）

1. `close()` 关闭 stdin writer → 子进程 stdin 收到 EOF
2. 子进程检测到 EOF 并退出
3. 若子进程未退出，TaskGroup 的 `cancel_handler` 会先 SIGTERM，5 秒后 SIGKILL
4. `close()` 关闭 stdout reader，标记 `closed = true`

### 使用示例

```moonbit
async fn main {
  @async.with_task_group(fn(group) {
    let stdio_client = StdioClientTransport::new(
      cmd="moon",
      args=["run", "path/to/server"],
    )
    stdio_client.start(group)
    let transport = AnyTransport::StdioClient(stdio_client)
    let client = MCPClient::new(
      name="my-host",
      version="1.0.0",
      transport~,
    )

    match client.initialize() {
      Ok(server_info) => {
        println("Connected to \{server_info.name}")
        // 使用 client API...
      }
      Err(e) => println("Init failed: \{e}")
    }
    client.close()
  })
}
```

## 4.7 消息验证

```moonbit
pub fn validate_jsonrpc_message(message : String) -> Result[Unit, MCPError]
```

验证一个字符串是否为合法的 JSON-RPC 2.0 消息（必须包含 `jsonrpc: "2.0"` 和 `method`/`result`/`error` 之一）。`StdioTransport::send()` 内部自动调用此函数验证发出的消息。

## 4.8 自定义 Transport

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
  let json = n.to_jsonrpc_string()
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

## 4.9 跨平台支持

Transport 包通过 MoonBit 的 `targets` 机制支持条件编译：

| 文件 | native | wasm-gc |
|------|--------|---------|
| `transport.mbt` | ✅ | ✅ |
| `stdio.mbt` | ✅ | — |
| `stdio_client.mbt` | ✅ | — |
| `http_server.mbt` | ✅ | — |
| `http_client.mbt` | ✅ | — |
| `http_compliance_test.mbt` | ✅ | — |
| `unimplemented.mbt` | — | ✅（stub） |

在 wasm-gc 上，`StdioTransport::new()`、`StdioClientTransport::new()`、`HttpTransport::new()` 和 `HttpClientTransport::new()` 会 abort。`Transport` trait 和 `AnyTransport` 类型定义在 wasm-gc 上可用，但无法实际进行 I/O。
