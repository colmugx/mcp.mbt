# MoonBit MCP SDK

Type-safe [Model Context Protocol](https://modelcontextprotocol.io/) SDK for MoonBit.

**Version**: 0.17.5 · **Protocol**: 2026-07-28 (stateless) · **License**: Apache-2.0

## Protocol support and scope

The SDK targets MCP **2026-07-28** with stateless per-request metadata and MRTR. This branch includes complete content/tool/resource/prompt wire models, completion, sampling and form/URL elicitation models, trusted request context, cooperative cancellation, cache metadata preservation, and registry-aware HTTP header validation. Registering features controls the capabilities advertised by discovery; an empty registry must be enabled explicitly.

Tool input/output validation now compiles schemas once at registration and rejects invalid arguments before executing handlers. Successful structured output is validated when an output schema is declared. Closed objects, precise numeric constraints and local `$ref`/`$defs` are supported.

**Conformance work is still in progress:** the validator has an explicit partial 2020-12 profile; arbitrary remote/dynamic/unevaluated schemas, elicitation validation and some numeric-id/MRTR edge cases remain open. See the [conformance evidence and migration notes](docs/conformance.md) before relying on a complete-protocol guarantee.

Bearer tokens, server-side authentication hooks, and protected-resource metadata are supported. OAuth authorization client lifecycle, PKCE, dynamic client registration, and token refresh management are **not included**.

## Installation

```bash
moon add colmugx/mcp
```

For this development revision, use the workspace and its checked-out `json-schema.mbt`
module. The validator dependency must be published and a standalone build verified
before releasing this SDK revision; the existing published SDK is not evidence that
these workspace changes are already available through the registry.

## Quick Start

### Server

```moonbit
async fn main {
  @mcp.MCPServer::MCPServer("demo-server", "1.0.0")
    .tool("echo", "Echo text", Json::object({ "type": "object" }), fn(_context, args) {
      let text = match args {
        Object(obj) =>
          match obj.get("text") {
            Some(String(value)) => value
            _ => ""
          }
        _ => ""
      }
      Ok(@mcp.ToolResult::text(text))
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
| [Client Guide](public/docs/05-client-guide.md) | Connections, MRTR input handlers, notifications, and legacy compatibility |
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
