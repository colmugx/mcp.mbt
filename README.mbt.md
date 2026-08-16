# MoonBit MCP SDK

Type-safe [Model Context Protocol](https://modelcontextprotocol.io/) SDK for MoonBit.

**Version**: 0.15.0 · **Protocol**: 2026-07-28 (stateless) · **License**: Apache-2.0

## Installation

```bash
moon add colmugx/mcp
```

## Quick Start

### Server

```moonbit
async fn main {
  @mcp.MCPServer::MCPServer("demo-server", "1.0.0")
    .tool("echo", "Echo text", Json::object({}), fn(args) {
      let text = match args {
        Object(obj) =>
          match obj.get("text") {
            Some(String(value)) => value
            _ => ""
          }
        _ => ""
      }
      Ok(@tool.ToolResult::text(text))
    })
    .run_stdio()
}
```

Use `.run_http(port=4240, path="/mcp")` for Streamable HTTP.

### Client

```moonbit
async fn main {
  match @mcp.MCPClient::connect_http(
    url="http://localhost:4240/mcp",
    name="demo-client",
    version="1.0.0",
  ) {
    Ok(client) => {
      // Optional one-shot discovery of server identity/capabilities.
      ignore(client.discover())
      match client.list_tools() {
        Ok(result) => for tool in result.tools { println(tool.name) }
        Err(e) => println(e.message())
      }
      client.close()
    }
    Err(e) => println("connect failed: \{e.message()}")
  }
}
```

For local subprocess servers, use `MCPClient::connect_stdio(cmd~, args?, name~, version~, extra_env?, group~)`.

### Host

```moonbit
async fn main {
  let host = @mcp.MCPHost::MCPHost(name="my-host", version="1.0.0")
  @async.with_task_group(group => {
    ignore(host.connect_stdio(name="local", cmd="moon", args=["run", "server"], group~))
    ignore(host.connect_http(name="remote", url="http://localhost:4240/mcp"))
    match host.list_tools() {
      Ok(result) => for tool in result.tools { println(tool.name) } // local.echo
      Err(e) => println(e.message())
    }
    ignore(host.call_tool("local.echo", arguments="{\"text\":\"hello\"}"))
    host.close_all()
  })
}
```

Host tool names are qualified as `connection.tool` so multiple servers can expose the same tool name without collision.

## Documentation

| Document | Description |
|----------|-------------|
| [Quickstart](public/docs/01-quickstart.md) | Server, client, and host setup |
| [Protocol Types](public/docs/02-protocol-types.md) | JSON-RPC, errors, and MCP types |
| [Server Guide](public/docs/03-server-guide.md) | High-level server API and runtime behavior |
| [Transport Reference](public/docs/04-transport-reference.md) | Advanced transport internals |
| [Client Guide](public/docs/05-client-guide.md) | `MCPClient::connect_*` and bidirectional mode |
| [Architecture](public/docs/06-architecture.md) | Protocol, runtime, transport, application layers |
| [Host Guide](public/docs/07-host-guide.md) | `MCPHost` named connections and routing |
| [Migration 0.15](MIGRATION-0.15.md) | 2025-11-25 → 2026-07-28 migration, node by node |
| [Migration 0.14](MIGRATION-0.14.md) | Breaking changes from 0.13.x |

## API Direction

The default public path is intentionally small:

- `MCPServer` for serving tools, resources, and prompts.
- `MCPClient` for one server connection.
- `MCPHost` for multiple named server connections.
- `colmugx/mcp/client/legacy` for talking to 2025-11-25-era servers (`LegacyClient`).

Transports and request builders are advanced/internal details. Existing low-level imports may still be useful for SDK contributors, but application code should prefer the high-level APIs above.

## License

Apache-2.0
