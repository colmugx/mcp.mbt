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
| Client stdio | yes | yes | yes (Node/Bun) | stub |
| Client HTTP | yes | yes | yes | stub |

Pure protocol code (types, codecs, JSON-RPC logic) is target-independent. Stubs compile but abort at runtime. The primary supported target is native; js exercises real HTTP and subprocess stdio clients plus the protocol suite.

## Runtime semantics

The SDK uses four concrete I/O shapes:

| Shape | Owner | Semantics |
|-------|-------|-----------|
| Server stdio | `MCPServer` | newline-delimited JSON-RPC, serialized output queue |
| Server HTTP | `MCPServer` | per-request reply queue, Streamable HTTP/SSE |
| Client stdio | `MCPClient` | child process stdin/stdout pipes |
| Client HTTP | `MCPClient` | POST request/response plus optional SSE events |

The old generic `send`/`receive String` mental model is no longer the design center. The runtime owns request IDs, pending responses, notification dispatch, and reply ownership.

## HTTP server

Each request to the MCP endpoint arrives with its payload, reply queue, trusted principal, and cancellation token. Custom runtimes must use `receive_authenticated_request()` and retain this envelope; the compatibility `receive_request()` pair omits identity and cancellation and must not be used for authenticated dispatch.

SSE has a single socket writer. Keepalive comments are flushed every 15 seconds by default (`HttpTransport(..., keepalive_interval_ms?)` for custom runtimes), so a disconnected peer is detected without reading or discarding pipelined requests. Write failure cancels the envelope token and closes its reply queue; both waiting consumers and blocked producers unwind. No second HTTP response is written after a stream has started. Cancellation detection may require more than one keepalive write, depending on the socket's close reporting.

Every request is Origin-checked to prevent DNS rebinding (see the Streamable HTTP security notes in the spec):

- No `Origin` header: allowed (non-browser clients).
- `Origin` present without an allowlist: only loopback origins pass (`127.0.0.1`, `localhost`, `[::1]`, any port, `http`/`https`).
- `AuthConfig` with `allowed_origins` (set via `MCPServer::with_auth`): exact match against the configured list; the allowlist replaces the loopback default.

Invalid origins get `403 Forbidden`.

### Header/body consistency

Standard headers (`MCP-Protocol-Version`, `Mcp-Method`, and applicable `Mcp-Name`) are checked against the body before dispatch. `MCPServer` installs a live tool-schema resolver in its HTTP transport so recognized `Mcp-Param-*` headers are checked against the exact nested property paths annotated with `x-mcp-header`.

A present non-null annotated argument requires its header. Missing or null arguments require omission. Header names are case-insensitive; string/boolean values are case-sensitive, and integers are compared numerically without Int32 truncation. Base64 sentinels are decoded once as UTF-8; malformed encodings, duplicate recognized values, mismatches, and missing required headers return **HTTP 400 with JSON-RPC `-32020` (`HeaderMismatch`)** before a handler runs. Unrecognized `Mcp-Param-*` headers are ignored, as the protocol requires.

Custom runtimes that bypass `MCPServer` must install `HttpTransport::set_tool_schema_resolver((String) -> Json?)` before accepting tool calls; otherwise the transport cannot recognize tool-specific headers. The shared pure `validate_tool_header_schema` and `validate_tool_parameter_headers` helpers are available to gateway implementations. These checks do not replace tool input/output JSON Schema validation.

See [MCP 2026-07-28 Streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http#server-behavior-for-custom-headers) for the normative mirroring and validation rules.

## HTTP client

Responses are dispatched by JSON-RPC `id` through the client runtime's pending map, including ordinary calls made before `run()`. Temporary and persistent response pumps share one read owner; request-scoped notifications are dispatched without consuming a pending response slot. Avoid depending on single-slot response cache fields or constructing client transports by hand.

The SSE reader preserves incomplete UTF-8 sequences across arbitrary network chunks, accepts a leading BOM, and rejects malformed/truncated sequences rather than treating them as EOF. Comment-only keepalives do not end the stream.

## Stdio client

Stdio client connections spawn a child process inside a caller-provided task group. Native and JS writers serialize complete newline-delimited frames, including cancellation notifications; failed partial writes close the transport rather than append another frame to damaged data. Best-effort cancellation notification delivery has a one-second bound so backpressure cannot indefinitely delay the cancelled caller.

The high-level helper starts the process and returns a connected `MCPClient` after protocol-era discovery (or the legacy initialization path when selected):

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
