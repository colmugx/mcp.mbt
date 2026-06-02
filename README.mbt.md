# MoonBit MCP SDK

Type-safe [Model Context Protocol](https://modelcontextprotocol.io/) (MCP 2025-11-25) server and client implementation in MoonBit.

**Version**: 0.12.0 · **Protocol**: 2025-11-25 · **License**: Apache-2.0

## Installation

```bash
moon add colmugx/mcp
```

Requires `moonbitlang/async` (auto-resolved as a dependency).

## Quick Start

### Server

```moonbit
// 1. Define a tool
struct EchoTool {}
pub impl Tool for EchoTool with name(_) -> String { "echo" }
pub impl Tool for EchoTool with description(_) -> String { "Echo input" }
pub impl Tool for EchoTool with params(_) -> Array[ParamDef] {
  [ParamDef::{ name: "text", schema: @core.str_schema(desc="Text"), required: true }]
}
pub impl Tool for EchoTool with async execute(_, args) -> ToolResult {
  match @core.get_string(args, "text") {
    Ok(t) => @tool.ToolResult::text("Echo: " + t)
    Err(_) => @tool.ToolResult::error("Missing 'text'")
  }
}

// 2. Create and run
fn main {
  @mcp.mcp_server(name="my-server", version="1.0.0")
    .with_tool(EchoTool::{})
    .run_stdio()  // or .run_http(port=4240)
}
```

**Claude Desktop** — add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "moon",
      "args": ["run", "path/to/server"]
    }
  }
}
```

### Client

```moonbit
async fn main {
  let transport = @transport.AnyTransport::HttpClient(
    @transport.HttpClientTransport::new("http://localhost:4240/mcp"),
  )
  let client = MCPClient::new(name="my-client", version="1.0.0", transport~)

  match client.initialize() {
    Ok(info) => {
      println("Connected to \{info.name}")
      match client.list_tools() {
        Ok(result) => for t in result.tools { println("  \{t.name}") }
        Err(e) => println("Error: \{e.message()}")
      }
      match client.call_tool("echo", arguments="{\"text\":\"hello\"}") {
        Ok(result) => for item in result.content {
          match item { Text(t) => println(t) _ => () }
        }
        Err(e) => println("Error: \{e.message()}")
      }
    }
    Err(e) => println("Init failed: \{e.message()}")
  }
  client.close()
}
```

For bidirectional mode (handling server-initiated requests), see [Client Guide](public/docs/05-client-guide.md).

## Feature Checklist

MCP 2025-11-25 compliance status:

### Protocol Primitives
- [x] JSON-RPC 2.0 (RequestId Int/Str, error codes)
- [x] Lifecycle (initialize + initialized notification)
- [x] Ping

### Server Capabilities
- [x] Tools (list, call, concurrent execution via TaskGroup)
- [x] Resources (list, read, subscribe, unsubscribe)
- [x] Prompts (list, get)
- [x] Logging (setLevel)
- [x] Notifications (tools/resources/prompts list_changed)
- [ ] Completions (server-side handler)

### Client Capabilities
- [x] Sampling (`on_sampling` handler, CreateMessageRequest/Result)
- [x] Roots (`on_roots` handler, Root type)
- [x] Elicitation (`on_elicitation` handler, ElicitationRequest/Result)

### Transports
- [x] STDIO (server + client)
- [x] HTTP/SSE server (Streamable HTTP, session management)
- [x] HTTP Client (SSE POST, DELETE session, Last-Event-ID)
- [ ] WebSocket

### Advanced
- [x] Pagination (cursor/nextCursor on all list methods)
- [x] Bidirectional event loop (`client.run(group)`)
- [x] 7 notification types (progress, cancelled, resource_updated, etc.)
- [x] ContentItem (Text, Image, ResourceLink, EmbeddedResource Text/Blob)
- [x] SchemaBuilder fluent API

### Production
- [x] Concurrent request handling (@async.TaskGroup)
- [x] Error handling (MCPError hierarchy with JSON-RPC error codes)
- [x] Schema caching (stringified once at registration)
- [x] Session management (Mcp-Session-Id, HTTP DELETE)
- [x] Cross-platform protocol layer (wasm-gc targets)

### Not Yet Implemented
- [ ] Tasks (experimental)
- [ ] OAuth/CIMD authentication
- [ ] WebSocket transport
- [ ] Server-side completions handler

## Documentation

| Document | Description |
|----------|-------------|
| [Quickstart](public/docs/01-quickstart.md) | 5-minute setup guide |
| [Protocol Types](public/docs/02-protocol-types.md) | Type reference (JSON-RPC, errors, ContentItem) |
| [Server Guide](public/docs/03-server-guide.md) | Tool/Resource/Prompt registration, SchemaBuilder |
| [Transport Reference](public/docs/04-transport-reference.md) | STDIO, HTTP/SSE, custom transport |
| [Client Guide](public/docs/05-client-guide.md) | Client API, pagination, bidirectional communication |
| [Architecture](public/docs/06-architecture.md) | Three-layer design, cross-platform, performance |
| [Host Guide](public/docs/07-host-guide.md) | Multi-server host pattern |

**Other**: [CHANGELOG](CHANGELOG.md) · [Migration Guide](MIGRATION-0.5.md) · [Contributing](CONTRIBUTING.md) · [MCP Spec](https://modelcontextprotocol.io/specification/)

## License

Apache-2.0
