# 7. Host 开发指南

MCP 架构中，**Host** 是管理多个 Client 连接的应用程序。每个 `MCPClient` 与一个 Server 保持 1:1 连接，Host 负责创建和管理多个 Client 实例。

```
┌─────────────────── Host ───────────────────┐
│                                             │
│  ┌───────────────┐  ┌───────────────┐      │
│  │  MCPClient A  │  │  MCPClient B  │ ...  │
│  └───────┬───────┘  └───────┬───────┘      │
│          │                  │               │
├──────────┼──────────────────┼───────────────┤
│          │ Transport        │ Transport     │
│    StdioClientTransport    HttpClientTransport    │
│          │                  │               │
├──────────┼──────────────────┼───────────────┤
│  ┌───────▼───────┐  ┌──────▼────────┐      │
│  │  Server A     │  │  Server B     │      │
│  │  (子进程)      │  │  (远程 HTTP)   │      │
│  └───────────────┘  └───────────────┘      │
└─────────────────────────────────────────────┘
```

## 7.1 为什么是 1:1

MCP 规范中，一个 Client 连接对应一个 Transport（一条通信通道）。`MCPClient` 封装了这条通道上的 JSON-RPC 协议：请求 ID 自增、初始化握手、消息序列化。

多 Server 场景不是在 Client 内部加多个 Transport，而是创建多个 Client 实例：

```moonbit
// ❌ 不存在这样的设计
let client = MCPClient::new(...)
client.add_transport(server_a)
client.add_transport(server_b)

// ✅ 正确做法：每个 server 一个 client
let client_a = MCPClient::new(name="host", version="1.0", transport~: transport_a)
let client_b = MCPClient::new(name="host", version="1.0", transport~: transport_b)
```

## 7.2 基础 Host 模式

```moonbit
async fn main {
  @async.with_task_group(fn(group) {
    // 连接 1：本地 stdio server（spawn 子进程）
    let stdio_client = @transport.StdioClientTransport::new(
      cmd="moon",
      args=["run", "path/to/server"],
    )
    stdio_client.start(group)
    let stdio_transport = @transport.AnyTransport::StdioClient(stdio_client)
    let local_client = MCPClient::new(
      name="my-host",
      version="1.0.0",
      transport~: stdio_transport,
    )

    // 连接 2：远程 HTTP server
    let http_transport = @transport.AnyTransport::HttpClient(
      @transport.HttpClientTransport::new(base_url="http://remote-server:4240/mcp"),
    )
    let remote_client = MCPClient::new(
      name="my-host",
      version="1.0.0",
      transport~: http_transport,
    )

    // 分别初始化
    match local_client.initialize() {
      Ok(info) => println("[local] Connected to \{info.name}")
      Err(e) => println("[local] Failed: \{e}")
    }
    match remote_client.initialize() {
      Ok(info) => println("[remote] Connected to \{info.name}")
      Err(e) => println("[remote] Failed: \{e}")
    }

    // 分别使用
    let local_tools = local_client.list_tools()
    let remote_tools = remote_client.list_tools()

    // 清理
    local_client.close()
    remote_client.close()
  })
}
```

## 7.3 连接管理

### 封装 Host 结构体

对于需要管理多个连接的应用，推荐封装一个 Host 结构体：

```moonbit
struct HostConnection {
  name : String
  client : MCPClient
  server_info : @types.ServerInfo
}

fn HostConnection::new(
  name~ : String,
  client~ : MCPClient,
  server_info~ : @types.ServerInfo,
) -> HostConnection {
  { name, client, server_info }
}

struct MCPHost {
  host_name : String
  host_version : String
  connections : Map[String, HostConnection]
}

fn MCPHost::new(name~ : String, version~ : String) -> MCPHost {
  { host_name: name, host_version: version, connections: Map::default() }
}
```

### 连接 Server

```moonbit
async fn MCPHost::connect(
  self : MCPHost,
  name : String,
  transport : @transport.AnyTransport,
) -> Result[@types.ServerInfo, @types.MCPError] {
  let client = MCPClient::new(
    name=self.host_name,
    version=self.host_version,
    transport~,
  )
  let server_info = client.initialize() catch {
    e => { client.close(); return Err(e) }
  }
  self.connections.set(name, HostConnection::new(
    name~,
    client~,
    server_info~,
  ))
  Ok(server_info)
}
```

### 聚合操作

```moonbit
/// 从所有连接的 server 聚合 tools 列表
async fn MCPHost::list_all_tools(self : MCPHost) -> Array[(String, ListToolsResult)] {
  self.connections
  .to_array()
  .filter_map(fn((name, conn)) {
    match conn.client.list_tools() {
      Ok(result) => Some((name, result))
      Err(_) => None
    }
  })
}

/// 在所有 server 中查找并调用指定 tool
async fn MCPHost::call_tool(
  self : MCPHost,
  tool_name : String,
  arguments? : String = "{}",
) -> Result[CallToolResult, @types.MCPError] {
  let entries = self.connections.to_array()
  // 在第一个找到该 tool 的 server 上调用
  for entry in entries {
    let (_, conn) = entry
    match conn.client.list_tools() {
      Ok(tools_result) =>
        if tools_result.tools.exists(fn(t) { t.name == tool_name }) {
          return conn.client.call_tool(tool_name, arguments~)
        }
      Err(_) => ()
    }
  }
  Err(@types.MethodNotFound("Tool not found on any server: " + tool_name))
}
```

### 清理

```moonbit
fn MCPHost::close_all(self : MCPHost) -> Unit {
  for entry in self.connections {
    let (_, conn) = entry
    conn.client.close()
  }
}
```

## 7.4 双向通信

当 server 需要向 client 主动发起请求（如 sampling、roots、elicitation）时，可使用 client 的 `run(group)` 事件循环模式：

```moonbit
@async.with_task_group(fn(group) {
  let client = MCPClient::new(name="host", version="1.0.0", transport~)
    .on_roots(fn() {
      Ok([{ uri: "file:///workspace", name: Some("workspace") }])
    })
    .on_notification({
      ..NotificationHandlers::empty(),
      on_tools_changed: Some(fn() { println("Tools changed!") }),
    })

  // 在 group 上 spawn 请求任务
  group.spawn_bg(() => {
    match client.list_tools() {
      Ok(result) => // 处理结果
      Err(e) => ...
    }
  })

  // run() 自动初始化并进入事件循环
  client.run(group)
})
```

## 7.5 Transport 选择

| 场景 | Transport | 说明 |
|------|-----------|------|
| 本地子进程 server | `StdioClientTransport` | Host spawn server 作为子进程，通过 stdin/stdout 管道通信 |
| 远程 HTTP server | `HttpClientTransport` | 连接到远程 MCP server 的 HTTP 端点 |
| 自定义通信 | 实现 `Transport` trait | WebSocket、IPC、内存等 |

> **注意：** `StdioTransport` 绑定当前进程的 stdin/stdout，仅用于 MCP **server** 端。Host 连接本地 server 应使用 `StdioClientTransport`。

### 子进程模式（Claude Desktop 模式）

Claude Desktop 等 MCP host 通过启动子进程来运行 stdio server：

```
Host (Claude Desktop)
  │
  ├── StdioClientTransport(cmd="moon", args=["run", "path/to/server"])
  │     └── stdin/stdout pipe ←→ MCPClient
  │
  ├── StdioClientTransport(cmd="npx", args=["@modelcontextprotocol/server-filesystem"])
  │     └── stdin/stdout pipe ←→ MCPClient
  │
  └── HttpClientTransport(base_url="https://remote-mcp.example.com/mcp")
        └── HTTP POST/SSE ←→ MCPClient
```

### HTTP 模式

连接到已运行的 HTTP server：

```
Host
  │
  ├── HttpClientTransport("http://localhost:4240/mcp")
  │     └── POST /mcp (JSON-RPC)
  │     └── GET /mcp (SSE notifications)
  │
  └── HttpClientTransport("http://other-server:8080/api")
        └── POST /api (JSON-RPC)
        └── GET /api (SSE notifications)
```

## 7.6 完整 Host 示例

```moonbit
async fn main {
  @async.with_task_group(fn(group) {
    let host = MCPHost::new(name="my-host", version="1.0.0")

    // 连接本地 stdio server（spawn 子进程）
    let stdio_client = @transport.StdioClientTransport::new(
      cmd="moon",
      args=["run", "path/to/server"],
    )
    stdio_client.start(group)
    match host.connect(
      "local",
      @transport.AnyTransport::StdioClient(stdio_client),
    ) {
      Ok(info) => println("[local] Connected to \{info.name}")
      Err(e) => println("[local] Failed: \{e}")
    }

    // 连接远程 HTTP server
    match host.connect(
      "remote",
      @transport.AnyTransport::HttpClient(
        @transport.HttpClientTransport::new(base_url="http://localhost:4240/mcp"),
      ),
    ) {
      Ok(info) => println("[remote] Connected to \{info.name}")
      Err(e) => println("[remote] Failed: \{e}")
    }

    // 聚合所有 server 的 tools
    let all_tools = host.list_all_tools()
    for entry in all_tools {
      let (name, result) = entry
      println("[\{name}] \{result.tools.length()} tools available")
    }

    // 调用 tool（自动路由到拥有该 tool 的 server）
    match host.call_tool("echo", arguments="{\"text\":\"Hello!\"}") {
      Ok(result) => println("[call] \{result}")
      Err(e) => println("[error] \{e}")
    }

    host.close_all()
  })
}
```

## 7.7 设计原则

| 原则 | 体现 |
|------|------|
| 1:1 连接 | `MCPClient` 绑定一个 `Transport`，职责单一 |
| 组合优于继承 | Host 通过持有多个 `MCPClient` 实现多连接 |
| 数据驱动 | `HostConnection` 是纯数据结构，`MCPHost` 通过函数操作 |
| 无隐式状态 | 所有连接显式创建、显式管理、显式清理 |
