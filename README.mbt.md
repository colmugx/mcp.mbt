# MoonBit MCP Server SDK

A comprehensive Model Context Protocol (MCP) server implementation in MoonBit, enabling easy integration of AI tools with MCP clients like Claude Desktop.

## Features

- **🔌 Dual Transport Support**: STDIO (for Claude Desktop) and HTTP with streaming
- **🛠️ Simple Tool API**: Define tools using the trait-based `Tool` interface
- **📝 Type-Safe Schema Generation**: Automatic JSON Schema generation from parameter definitions
- **✅ Comprehensive Testing**: 87+ unit and integration tests
- **🚀 Production Ready**: Error handling, validation, and protocol compliance (MCP 2025-06-18)
- **📦 Zero-Dependencies**: Built on MoonBit standard library

## Installation

```bash
# Add to your moon.pkg.json dependencies
{
  "dependencies": [
    { "path": "path/to/mcp.mbt", "url": "https://github.com/colmugx/mcp.mbt" }
  ]
}
```

## Quick Start

### 1. Define Your Tool

```moonbit
struct EchoTool {}

impl Tool for EchoTool with name(_self : EchoTool) -> String {
  "echo"
}

impl Tool for EchoTool with description(_self : EchoTool) -> String {
  "Echoes back the input text"
}

impl Tool for EchoTool with params(_self : EchoTool) -> Array[ParamDef] {
  [string_param("text", "The text to echo back")]
}

impl Tool for EchoTool with execute(_self : EchoTool, args : Json) -> ToolResult {
  let text = match get_string(args, "text") {
    Ok(t) => t
    Err(_) => return ToolResult::error("Missing 'text' parameter")
  }
  ToolResult::text("Echo: " + text)
}
```

### 2. Create and Run Server

```moonbit
fn main() {
  // Create server
  let server = MCPServer::new("my-mcp-server", "1.0.0")

  // Register tool
  server.register_trait_tool(EchoTool::{})

  // Choose transport
  let transport = AnyTransport::Stdio(StdioTransport::new())
  // OR for HTTP:
  // let transport = AnyTransport::Http(HttpTransport::new(port=4240))

  // Run server
  server.run(transport) catch {
    e => @stdio.stderr.write("Error: " + e.to_string())
  }
}
```

### 3. Test with Claude Desktop

Add to your Claude Desktop config (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "my-server": {
      "command": "moon",
      "args": ["run", "path/to/your_server.mbt"]
    }
  }
}
```

## Architecture

### Core Components

```
colmugx/mcp
├── src/
│   ├── tool.mbt           # Tool trait, ToolResult, helpers
│   ├── schema.mbt         # Schema DSL (ParamDef, expand_params_to_json)
│   ├── args.mbt           # ArgsParser trait implementation
│   ├── server/
│   │   ├── server.mbt     # MCPServer, JSON-RPC handlers
│   │   ├── registry.mbt   # ToolRegistry (internal)
│   │   └── tool_bridge.mbt # Tool trait integration
│   ├── transport/
│   │   ├── transport.mbt  # Transport trait, AnyTransport enum
│   │   ├── stdio.mbt      # STDIO transport implementation
│   │   └── http.mbt       # HTTP transport implementation
│   └── types/
│       └── types.mbt      # Error types, JsonRpcRequest
```

### Design Philosophy

The SDK follows these principles:

1. **Trait-Based Tools**: Use the `Tool` trait for type-safe, composable tool definitions
2. **Maria-Inspired Safety**: Noraise patterns and explicit error handling
3. **Transport Agnostic**: Same tools work with STDIO or HTTP
4. **Protocol Compliant**: Full MCP 2025-06-18 compliance

## API Reference

### Tool Trait

```moonbit
pub(open) trait Tool {
  name(Self) -> String
  description(Self) -> String
  params(Self) -> Array[ParamDef]
  execute(Self, Json) -> ToolResult
}
```

### ToolResult

```moonbit
// Success with text
ToolResult::text("Success message")

// Error result
ToolResult::error("Error message")

// Success with multiple content items
ToolResult::success([ContentItem::Text("Line 1"), ContentItem::Text("Line 2")])
```

### Parameter Definitions

```moonbit
// Required parameters
string_param("name", "Description")
number_param("count", "Description")
boolean_param("enabled", "Description")

// Optional parameters
optional_string_param("nickname", "Optional description")
optional_number_param("limit", "Optional limit")
optional_boolean_param("verbose", "Verbose output")
```

### Argument Parsing

```moonbit
// Required fields
let name = get_string(args, "name")  // Result<String, MCPError>
let count = get_number(args, "count")  // Result<Double, MCPError>

// Optional fields
let nickname = get_optional_string(args, "nickname")  // Result<Option<String>, MCPError>
```

### MCPServer

```moonbit
// Create server
let server = MCPServer::new("server-name", "1.0.0")

// Register tools using Tool trait
server.register_trait_tool(MyTool::{})

// Register tools using legacy handler API
server.register_tool(
  name="tool_name",
  description="Tool description",
  input_schema=Json::object({...}),
  handler=async fn(args) { Ok(ToolResult::text("result")) }
)

// Run server
server.run(transport)  // Blocks until transport closes
```

### Transports

```moonbit
// STDIO (for Claude Desktop)
let stdio = AnyTransport::Stdio(StdioTransport::new())

// HTTP (for web clients)
let http = AnyTransport::Http(HttpTransport::new(
  port=4240,
  endpoint_path="/mcp"
))

// Both support the same interface
transport.send(message)
transport.receive()  // async
transport.close()
```

## Examples

The SDK includes comprehensive examples:

### 1. STDIO Server ([`examples/stdio_server.mbt`](examples/stdio_server.mbt))
Minimal MCP server using STDIO transport for Claude Desktop integration.

### 2. HTTP Server ([`examples/http_server.mbt`](examples/http_server.mbt))
HTTP-based MCP server with streaming support for web clients.

### 3. Real-World Tools ([`examples/real_world_tools.mbt`](examples/real_world_tools.mbt))
Practical tools demonstrating:
- Calculator with arithmetic operations
- Text processor (uppercase, lowercase, reverse, word count)
- Data converter (Base64, URL encoding)

### 4. Advanced Patterns ([`examples/advanced_patterns.mbt`](examples/advanced_patterns.mbt))
Production patterns including:
- Tool composition and workflows
- Stateful tools
- Input validation and error handling
- Multi-output tools
- Tool aliases and wrappers

## Testing

### Run All Tests

```bash
moon test
```

### Test Coverage

- **87 tests** covering all major components
- Unit tests for Tool, Schema, Args parsing
- Integration tests for Server, Registry
- Transport layer tests for STDIO and HTTP

### Test Files

- [`src/tool_test.mbt`](src/tool_test.mbt) - Tool trait, ToolResult, helpers (32 tests)
- [`src/schema_test.mbt`](src/schema_test.mbt) - Schema DSL, ParamDef (14 tests)
- [`src/args_test.mbt`](src/args_test.mbt) - ArgsParser implementation (14 tests)
- [`src/server/server_test.mbt`](src/server/server_test.mbt) - MCPServer, ToolRegistry (14 tests)
- [`src/transport/transport_test.mbt`](src/transport/transport_test.mbt) - Transport implementations (13 tests)

## MCP Protocol Support

### Supported Methods

- ✅ `initialize` - Server initialization handshake
- ✅ `tools/list` - List available tools
- ✅ `tools/call` - Execute a tool

### Protocol Version

MCP 2025-06-18 (latest)

### JSON-RPC Version

2.0

## Error Handling

The SDK provides comprehensive error handling:

```moonbit
match get_string(args, "required_field") {
  Ok(value) => // Use value
  Err(error) => return ToolResult::error(error.message())
}
```

Error types:
- `ParseError` - Invalid JSON
- `InvalidRequest` - Malformed request
- `MethodNotFound` - Unknown method
- `InvalidParams` - Invalid parameters
- `InternalError` - Server error

## Best Practices

### 1. Tool Naming

Use descriptive, lowercase names with underscores:

```moonbit
// Good
"search_documents"
"analyze_sentiment"

// Avoid
"SearchDocuments"
"searchDocuments"
```

### 2. Parameter Validation

Always validate parameters in `execute`:

```moonbit
impl Tool for MyTool with execute(_self : MyTool, args : Json) -> ToolResult {
  let input = match get_string(args, "input") {
    Ok(i) => i
    Err(_) => return ToolResult::error("Missing 'input' parameter")
  }

  if input.is_empty() {
    return ToolResult::error("'input' cannot be empty")
  }

  // Process input...
}
```

### 3. Error Messages

Provide clear, actionable error messages:

```moonbit
// Good
ToolResult::error("'count' must be a positive number")

// Avoid
ToolResult::error("Invalid count")
```

### 4. Schema Design

Use appropriate parameter types and descriptions:

```moonbit
impl Tool for MyTool with params(_self : MyTool) -> Array[ParamDef] {
  [
    string_param("query", "Full-text search query (supports quotes for phrases)"),
    optional_number_param("limit", "Maximum results to return (default: 10, max: 100)"),
    optional_string_param("sort", "Sort order: relevance, date, or title (default: relevance)"),
  ]
}
```

## Limitations and Future Work

### Current Limitations

1. **Async Testing**: MoonBit's test framework doesn't support async tests directly
   - Workaround: Integration tests cover async functionality through public APIs
2. **Resources/Prompts**: MCP Resources and Prompts not yet implemented
3. **Streaming SSE**: HTTP transport SSE streaming is a no-op placeholder

### Planned Features

- [ ] Resource support (file reading, listing)
- [ ] Prompt templates
- [ ] Sampling support
- [ ] Completion helpers
- [ ] Enhanced HTTP SSE streaming
- [ ] WebSocket transport

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass (`moon test`)
5. Submit a pull request

## License

[Specify your license here]

## Support

- **Issues**: Report bugs and feature requests on GitHub
- **Discussions**: Use GitHub Discussions for questions
- **Documentation**: See [`examples/`](examples/) directory for usage patterns

## Acknowledgments

Built with ❤️ in MoonBit. Implements the [Model Context Protocol](https://modelcontextprotocol.io/) by Anthropic.

---

**Version**: 1.0.0
**MCP Protocol**: 2025-06-18
**MoonBit**: Latest
