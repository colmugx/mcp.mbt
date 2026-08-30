# Transport Reference

Transports are advanced SDK internals in v0.14. Application code should normally use:

- `MCPServer::run_stdio()`
- `MCPServer::run_http(port?, path?)`
- `MCPClient::connect_http(...)`
- `MCPClient::connect_stdio(...)`
- `MCPHost::connect_http(...)`
- `MCPHost::connect_stdio(...)`

## Runtime Semantics

The SDK uses four concrete I/O shapes:

| Shape | Owner | Semantics |
|-------|-------|-----------|
| Server STDIO | `ServerRuntime` | newline-delimited JSON-RPC, serialized output queue |
| Server HTTP | `ServerRuntime` | per-request reply queue, Streamable HTTP/SSE |
| Client STDIO | `ClientRuntime` | child process stdin/stdout pipes |
| Client HTTP | `ClientRuntime` | POST request/response plus optional SSE events |

The old generic `send/receive String` mental model is no longer the design center. It remains useful for contributors, but runtime code is responsible for request IDs, pending responses, notification dispatch, and reply ownership.

## HTTP Server

HTTP server requests are received with a payload and a reply queue. Slow handlers can complete out of order because each request carries its own reply queue.

Every request to the MCP endpoint is Origin-checked for DNS rebinding prevention (spec basic/transports/streamable-http#security-endpoint). Invalid origins get `403 Forbidden`.

- No `Origin` header: allowed (non-browser clients).
- `Origin` present without an allowlist: only loopback origins pass (`127.0.0.1`, `localhost`, `[::1]`, any port, `http`/`https`).
- `AuthConfig` with `allowed_origins` (set via `MCPServer::with_auth`): exact match against the configured list; the allowlist replaces the loopback default.

## HTTP Client

Client responses are dispatched by JSON-RPC `id` through the client runtime pending map. Avoid relying on single-slot response cache fields or direct transport construction in application code.

## STDIO Client

STDIO client connections spawn a child process inside a caller-provided task group. The high-level helper starts the process, initializes the MCP session, and returns an `MCPClient`.

```moonbit
@async.with_task_group(group => {
  let client_result = @mcp.MCPClient::connect_stdio(
    cmd="moon",
    args=["run", "server"],
    name="client",
    version="1.0.0",
    group~,
  )
})
```

## Advanced Use

Direct imports from `colmugx/mcp/transport` are for SDK extensions, custom runtime experiments, and tests. The default documentation intentionally does not require `AnyTransport`.
