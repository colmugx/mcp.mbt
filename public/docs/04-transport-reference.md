# 4. Transport Reference

Transports are SDK internals. Application code should use:

- `MCPServer::run_stdio()` / `MCPServer::run_http(port?, path?)`
- `MCPClient::connect_http(...)` / `MCPClient::connect_stdio(...)`
- `MCPHost::connect_http(...)` / `MCPHost::connect_stdio(...)`

Direct imports from `colmugx/mcp/transport` are for SDK extensions, custom runtimes, and tests.

## Target support

| Capability | native | wasm | js | wasm-gc |
|------------|--------|------|-----|---------|
| Server stdio | yes | yes | stub | stub |
| Server HTTP | yes | yes | stub | stub |
| Client stdio | yes | yes | stub | stub |
| Client HTTP | yes | yes | yes | stub |

Pure protocol code (types, codecs, JSON-RPC logic) is target-independent. Stubs compile but abort at runtime. The primary supported target is native; js currently exercises the HTTP client and protocol suite.

## Runtime semantics

The SDK uses four concrete I/O shapes:

| Shape | Owner | Semantics |
|-------|-------|-----------|
| Server stdio | `ServerRuntime` | newline-delimited JSON-RPC, serialized output queue |
| Server HTTP | `ServerRuntime` | per-request reply queue, Streamable HTTP/SSE |
| Client stdio | `ClientRuntime` | child process stdin/stdout pipes |
| Client HTTP | `ClientRuntime` | POST request/response plus optional SSE events |

The old generic `send`/`receive String` mental model is no longer the design center. The runtime owns request IDs, pending responses, notification dispatch, and reply ownership.

## HTTP server

Each request to the MCP endpoint arrives with its payload and a reply queue, so slow handlers may complete out of order without crossing responses.

Every request is Origin-checked to prevent DNS rebinding (see the Streamable HTTP security notes in the spec):

- No `Origin` header: allowed (non-browser clients).
- `Origin` present without an allowlist: only loopback origins pass (`127.0.0.1`, `localhost`, `[::1]`, any port, `http`/`https`).
- `AuthConfig` with `allowed_origins` (set via `MCPServer::with_auth`): exact match against the configured list; the allowlist replaces the loopback default.

Invalid origins get `403 Forbidden`.

## HTTP client

Responses are dispatched by JSON-RPC `id` through the client runtime's pending map. Avoid depending on single-slot response cache fields or constructing client transports by hand.

## Stdio client

Stdio client connections spawn a child process inside a caller-provided task group. The high-level helper starts the process and returns an initialized `MCPClient`:

```moonbit
@async.with_task_group(group => {
  match
    @mcp.MCPClient::connect_stdio(
      cmd="moon",
      args=["run", "server"],
      name="client",
      version="1.0.0",
      group~,
    ) {
    Ok(client) => client.close()
    Err(e) => println(e.message())
  }
})
```
