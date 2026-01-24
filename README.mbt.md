# MoonBit MCP Server SDK

A type-safe Model Context Protocol (MCP) server implementation in MoonBit, enabling easy integration of AI tools with MCP clients like Claude Desktop.

**API Documentation**: Available inline with code examples
**Examples**: See `examples/` directory
**Status**: Experimental, API subject to change

## Installation

```bash
moon add colmugx/mcp
```

This package requires `moonbitlang/async` as a dependency.

## Quick Start

### 1. Define Your Tool

```moonbit
struct EchoTool {}

pub impl Tool for EchoTool with name(_self : EchoTool) -> String {
  "echo"
}

pub impl Tool for EchoTool with description(_self : EchoTool) -> String {
  "Echoes back the input text"
}

pub impl Tool for EchoTool with params(_self : EchoTool) -> Array[ParamDef] {
  [string_param("text", "The text to echo back")]
}

pub impl Tool for EchoTool with execute(_self : EchoTool, args : Json) -> ToolResult {
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
  let server = MCPServer::new("my-mcp-server", "1.0.0")
  server.register_trait_tool(EchoTool::{})

  // STDIO for Claude Desktop
  let transport = AnyTransport::Stdio(StdioTransport::new())

  server.run(transport) catch {
    e => @stdio.stderr.write("Error: " + e.to_string())
  }
}
```

### 3. Test with Claude Desktop

Add to `claude_desktop_config.json`:

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

## Features

### Core Protocol
- [x] Tools (list, call)
- [ ] Resources (list, read, subscribe, unsubscribe)
- [ ] Prompts (list, get)

### Transports
- [x] STDIO (for Claude Desktop)
- [x] HTTP with SSE streaming
- [ ] WebSocket

### Advanced Capabilities
- [ ] Logging
- [ ] Completions (argument autocompletion)
- [ ] Sampling (LLM completion requests)

### Notifications
- [x] Tools list changed
- [ ] Resources list changed
- [ ] Prompts list changed
- [ ] Resources updated
- [ ] Progress tracking

### Production Features
- [x] Basic error handling
- [ ] Structured logging (JSON)
- [ ] Metrics collection
- [ ] Health checks
- [ ] Authentication
- [ ] Rate limiting
- [ ] Caching

### Testing & Examples
- [x] Unit tests (87+ tests)
- [ ] Integration tests
- [ ] Resource examples
- [ ] Prompt examples
- [ ] Production deployment examples

### Developer Tools
- [ ] CLI tools (generator, validator, test client)
- [ ] Type generation from JSON Schema

## API Overview

### Tool Trait

```moonbit
pub(open) trait Tool {
  name(Self) -> String
  description(Self) -> String
  params(Self) -> Array[ParamDef]
  async execute(Self, Json) -> ToolResult
}
```

### Server

```moonbit
// Create server
let server = MCPServer::new("server-name", "1.0.0")

// Register tools
server.register_trait_tool(MyTool::{})

// Run server
server.run(transport)  // Blocks until transport closes
```

### Transports

```moonbit
// STDIO (Claude Desktop)
let stdio = AnyTransport::Stdio(StdioTransport::new())

// HTTP (web clients)
let http = AnyTransport::Http(HttpTransport::new(port=4240))
```

## Examples

The `@examples` package demonstrates all core SDK features with 5 example tools:

- **EchoTool** - Basic echo for testing connectivity
- **CalculateTool** - Calculator with arithmetic operations
- **TransformTextTool** - Text transformation (uppercase, lowercase, reverse, etc.)
- **AnalyzeTextTool** - Text analysis (word count, character count, etc.)
- **GetTimestampTool** - Get current timestamp in various formats

Run the example server:
```bash
moon run @examples/cmd/main
```

## Documentation

- **[TODO.md](TODO.md)** - Detailed implementation roadmap
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Contribution guidelines
- **[MCP Spec](https://modelcontextprotocol.io/specification/)** - Official specification

## License

Apache-2.0

## Support

- **Issues**: [GitHub Issues](https://github.com/colmugx/mcp.mbt/issues)
- **Discussions**: [GitHub Discussions](https://github.com/colmugx/mcp.mbt/discussions)
