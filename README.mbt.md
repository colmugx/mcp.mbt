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

## API Reference

### Tool Trait

```moonbit
pub(open) trait Tool {
  name(Self) -> String
  description(Self) -> String
  params(Self) -> Array[ParamDef]
  async execute(Self, Json) -> ToolResult
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

## License

Apache-2.0

## Support

- **Issues**: Report bugs and feature requests on GitHub
- **Discussions**: Use GitHub Discussions for questions
