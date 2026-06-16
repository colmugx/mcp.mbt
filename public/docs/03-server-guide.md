# Server Guide

## High-Level API

Create servers with `MCPServer(name, version)` and register capabilities with builder methods.

```moonbit
let server = @mcp.MCPServer("app", "1.0.0")
  .tool("echo", "Echo input", Json::object({}), fn(args) {
    Ok(@tool.ToolResult::text(args.stringify()))
  })
```

Trait-based tool/resource/prompt wrappers remain available through `with_tool`, `with_resource`, and `with_prompt`.

## Run Modes

```moonbit
server.run_stdio()
server.run_http(port=4240, path="/mcp")
```

The old `run(AnyTransport, group)` path is no longer the ordinary user API. The server runtime owns transport dispatch, task-group lifecycle, and response routing.

## Runtime Behavior

The server parses each JSON-RPC request once, then dispatches by parsed `method`.

Fast path methods are handled inline:

- `initialize`
- `ping`
- `tools/list`
- `resources/list`
- `prompts/list`

Potentially suspending methods are spawned on the task group:

- `tools/call`
- `resources/read`
- `prompts/get`

STDIO responses are serialized through one output queue. HTTP requests carry their own reply handle, so responses are returned to the matching request even when handlers complete out of order.

## Authentication

HTTP auth remains configured on the server:

```moonbit
server
  .with_auth(auth)
  .run_http(port=4240, path="/mcp")
```

See the transport reference for advanced HTTP details.
