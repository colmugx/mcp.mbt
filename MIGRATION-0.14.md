# Migration Guide: 0.13.x to 0.14.0

v0.14 is a breaking release focused on the high-level API: `MCPServer`, `MCPClient`, and `MCPHost`.

## Breaking Changes

- Application code should stop constructing `AnyTransport` for normal server/client setup.
- `MCPServer::run(transport, group)` is no longer the public server entry point.
- `MCPServer::run_http` now owns its task group: use `run_http(port?, path?)`.
- `MCPClient::new(..., transport~)` is no longer the public construction path.
- Request builder helpers are internal implementation details.
- Hand-written host structs should migrate to `MCPHost`.

## Server Migration

Before:

```moonbit
let transport = @transport.AnyTransport::Stdio(@transport.StdioTransport::new())
@async.with_task_group(group => {
  server.run(transport, group)
})
```

After:

```moonbit
server.run_stdio()
```

HTTP before:

```moonbit
@async.with_task_group(group => {
  server.run_http(port=4240, path="/mcp", group~)
})
```

HTTP after:

```moonbit
server.run_http(port=4240, path="/mcp")
```

Tool registration before:

```moonbit
server.register_tool("echo", "Echo text", schema, handler)
```

After:

```moonbit
let server = server.tool("echo", "Echo text", schema, handler)
```

## Client Migration

HTTP before:

```moonbit
let transport = @transport.AnyTransport::HttpClient(
  @transport.HttpClientTransport::new("http://localhost:4240/mcp"),
)
let client = @client.MCPClient::new(
  name="my-client",
  version="1.0.0",
  transport~,
)
ignore(client.initialize())
```

HTTP after:

```moonbit
let client = @client.MCPClient::connect_http(
  url="http://localhost:4240/mcp",
  name="my-client",
  version="1.0.0",
)
```

STDIO before:

```moonbit
@async.with_task_group(group => {
  let stdio = @transport.StdioClientTransport::new(cmd="server", args=[])
  stdio.start(group)
  let transport = @transport.AnyTransport::StdioClient(stdio)
  let client = @client.MCPClient::new(
    name="my-client",
    version="1.0.0",
    transport~,
  )
  ignore(client.initialize())
})
```

STDIO after:

```moonbit
@async.with_task_group(group => {
  let client = @client.MCPClient::connect_stdio(
    cmd="server",
    args=[],
    name="my-client",
    version="1.0.0",
    group~,
  )
})
```

## Host Migration

Before:

```moonbit
struct HostConnection {
  name : String
  client : @client.MCPClient
}
```

After:

```moonbit
let host = @client.MCPHost::new(name="my-host", version="1.0.0")
ignore(host.connect_http(name="remote", url="http://localhost:4240/mcp"))
ignore(host.list_tools())
ignore(host.call_tool("remote.echo", arguments="{\"text\":\"hello\"}"))
host.close_all()
```

Tool names are routed as `connection.tool`. This prevents collisions when multiple servers expose the same tool name.

## Advanced Transport Migration

If you are extending the SDK itself, direct transport imports remain available from `colmugx/mcp/transport`. Treat these as advanced internals:

- server STDIO
- server HTTP
- client STDIO
- client HTTP

Do not use transport fields such as HTTP response caches as application state. Client responses are owned by the client runtime pending map and dispatched by JSON-RPC id.
