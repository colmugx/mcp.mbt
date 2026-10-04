# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.17.5

Toolchain: MoonBit v0.10.9, `moonbitlang/async` 0.20.5 → 0.21.0.

### Added

- Compile-once tool input/output validation using the independent
  `colmugx/json-schema` library. Invalid arguments fail with `-32602` before
  handlers execute; successful results declaring an output schema must include
  matching structured output, or fail with `-32603`. Unsupported schemas fail
  registration explicitly; local `$ref`/`$defs` and exact decimal constraints
  are supported without claiming complete JSON Schema 2020-12 coverage.
- `parse_json` on the root facade preserves numeric lexemes for precise schemas
  and structured results. Argument, request, retry and result wire paths now
  preserve long decimals rather than validating rounded values.
- `extra_headers` on `MCPClient::connect_http` (and the legacy
  `connect_http` paths beneath it, plus `HttpClientTransport` directly):
  caller-supplied headers appended to every outgoing request — requests,
  notifications, and the legacy session DELETE — after the built-in set,
  with last-write-wins override of same-name built-ins (custom auth,
  tracing, routing). The same set rides the legacy-era fallback path so
  header-gated servers see identical headers on both protocol eras. A
  legacy initialize HTTP 4xx rejection now carries the server's response
  body in the raised `HttpError` (matching the modern transport) instead
  of a bare status line.
- Shared SSE scanner `@transport.read_sse_event`, built on `lexscan` over
  `@lexbuf.AsyncLexbuf` so line tokenization runs on the compiler-optimized
  regex path and patterns may span refill-chunk boundaries. Replaces both
  hand-rolled line parsers (modern + legacy transports). WHATWG-spec
  semantics: `\n`/`\r\n`/`\r` terminators, single-space stripping after the
  field colon, comment and unknown-field skipping, and an unterminated final
  line at EOF is dispatched as if terminated (the modern transport
  previously discarded it).
- Property-based tests via `@qc` for the protocol codecs: header-value
  sentinel roundtrip, base64 losslessness over UTF-8 bytes, the
  "encoder output is always a transmittable header value" invariant, and an
  SSE formatted-payload roundtrip over 200 random samples.
- JS target support: `moon check --target js --deny-warn` and
  `moon test --target js` are green (CI gates both). Native-only transports
  (`StdioTransport`, `StdioClientTransport`, server-side `HttpTransport`)
  are gated to `native`+`wasm` with a js stub file
  (`src/transport/unimplemented_js.mbt`) preserving the API surface;
  `HttpClientTransport` compiles and runs for real on js (fetch-based).
  Pure JSON-RPC/SSE logic (`JsonRpcKind`, `classify_jsonrpc_message`,
  `sse_event_line`, …) moved to the all-target `jsonrpc_logic.mbt`.
- `StdioClientTransport` is now real on the js target (one code path for
  node and Bun): the child process is spawned via `node:child_process`,
  stdout is bridged through `Readable.toWeb` + `js_async.ReadableStream`
  (cancellable `@io.Reader`), stdin writes go through `Writable.toWeb`
  with one awaited write per `send`, and graceful close mirrors the native
  two-phase lifecycle (stdin EOF, 5s kill timer). A watchdog task spawned
  into the caller's `TaskGroup` ties the child's lifetime to the group:
  group cancellation/failure/teardown reruns the close choreography and
  blocks until the child exits, so the child never outlives the group.
  All Node interop lives in inline `extern "js"` snippets using dynamic
  `import('node:...')`, bridged into coroutines via
  `@js_async.Promise::wait`.

### Changed

- Upgraded to `moonbitlang/async` 0.21.0 and migrated to the
  case-insensitive `@http.Headers` type: `response.headers.get("…")` no
  longer depends on the server's header casing, and the modern transport's
  `Mcp-Param-*` scan reads `k.0` instead of calling `to_lower` on the key.
- HTTP client cleanup migrated to `defer`/`errdefer`
  (`HttpClientTransport::send`/`send_notification`,
  `LegacyHttpSessionTransport::do_post`/`send`): every error path —
  including async cancellation — releases the connection exactly once, and
  the `body.text()` failure paths that previously leaked the client are
  covered. `do_post` uses `errdefer` because the client escapes via the
  return value on success; the other three own the client for their whole
  body, so plain `defer` is exact.
- `MCPError::message` uses `Show::to_string` explicitly (implicit method
  promotion is deprecated by the compiler).
- Packaging ignores moved from `moon.mod` `options(exclude)` (deprecated) to
  `.moonignore`.
- Example modules re-pinned to `colmugx/mcp@0.15.0` +
  `moonbitlang/async@0.21.0` (were four minors behind on mcp, four on
  async).

### Fixed

- `StdioClientTransport::start` no longer leaks the parent-held pipe ends
  when `@process.spawn` fails or is cancelled mid-start (previously two FDs
  per failed start; `errdefer` releases them while preserving ownership
  transfer into the transport on success).
- HTTP SSE responses now flush incrementally: the server's SSE branch never
  called `conn.flush()`, so subscription acknowledgements and events were
  buffered until `end_response` — long-lived `subscriptions/listen` streams
  sent zero bytes (not even response headers). Regression-tested with a
  deadlock-style probe in `sse_flush_io_test.mbt`.
- Cancellation errors are no longer swallowed by the HTTP transports: every
  error-translation `catch` in `HttpClientTransport` and the legacy session
  transport now checks `@async.is_being_cancelled()` and re-raises the
  original error, so `with_timeout` surfaces `TimeoutError` instead of a
  mistranslated `ReadError("Failed to get response: Cancelled")`. As a
  deliberate consequence, `send`/`send_notification` on
  `HttpClientTransport`/`AnyTransport`/`LegacyHttpSessionTransport` now
  declare a general `raise` instead of `raise @types.TransportError`.
  Regression-tested with stall-server timeout probes
  (`cancellation_io_test.mbt`, `http_cancellation_wbtest.mbt`).

- HTTP transports no longer queue keepalive SSE events as JSON-RPC
  messages. A stream that opens with an empty `data:` event or interleaves
  comment-only heartbeats (nowledge-mem opens every stream with `data:` +
  `id:` + `retry:`) previously desynced response matching — `initialize`
  parsed the empty string and failed with `Invalid initialize response`.
  New `@transport.sse_event_verdict` classifies each scanned event
  (message / skip / EOF) and both response loops (modern + legacy) consume
  it; a heartbeat that carries an `id` no longer ends the scan early.
- `connect_http` era probing no longer dies fatally on an HTTP 4xx rejection
  of the `server/discover` probe. Any 4xx whose body does not carry a
  modern JSON-RPC error now falls back to the legacy initialize handshake —
  servers implementing only the 2025-11-25 flow answer a non-initialize
  first message at the HTTP layer (nowledge-mem: `422 "Unexpected message,
  expect initialize"`). 5xx stays fatal: a broken server is not an
  era signal.
- Task cancellation aborting an in-flight `send_request` no longer swallows
  the cancellation into `InternalError("Receive failed")` /
  `InternalError("Response timeout")`. Both response-wait catches (event
  loop `queue.get`, direct-mode `receive`) now check
  `@async.is_being_cancelled()` and re-raise, after delivering a best-effort
  `notifications/cancelled` to the server (stdio client transports only,
  same gating as `cancel_request`; `requestId` is the string form of the
  internal Int request id, `reason="client aborted"`). The notification
  write is shielded with `protect_from_cancel` so the level-triggered
  cancellation cannot kill it mid-write; send failures are swallowed.
  Regression-tested in `request_cancel_io_wbtest.mbt` (real child process
  echoes the notification back).
### Removed

- Legacy `get_header_ci`/`extract_session_id` helpers (superseded by the
  case-insensitive `@http.Headers`) and the duplicate
  `parse_sse_event`/`read_sse_event` line parsers.

## [0.15.0] - 2026-08-09

Targets the MCP `2026-07-28` specification — the stateless revision that
removes the `initialize`/session handshake, replaces server-initiated
requests with Multi Round-Trip Requests (MRTR), and adds
`server/discover` + `subscriptions/listen`. Asymmetric strategy: the
server is 2026-07-28 only (clean cut); the client is modern-first with
legacy 2025-11-25 support isolated in `src/client/legacy/`.

### Added — Server (2026-07-28 only)

- `ProtocolVersion` constant (`"2026-07-28"`) as the single source of truth.
- **Per-request `_meta`**: every response carries
  `resultType` + `_meta.io.modelcontextprotocol/serverInfo`; every result that
  can be cached (`tools/list`, `prompts/list`, `resources/list`,
  `resources/read`, `server/discover`) carries `ttlMs` + `cacheScope`.
- **`server/discover`** RPC — returns supported versions, capabilities,
  identity. `is_fast_method` includes it.
- **`subscriptions/listen`** — long-lived stream replacing
  `resources/subscribe`/`unsubscribe` + the GET SSE endpoint. Server sends
  `notifications/subscriptions/acknowledged` first, then routes matching
  change notifications (`notify_{tools,resources,prompts}_list_changed`)
  tagged with `io.modelcontextprotocol/subscriptionId`.
- **MRTR (Multi Round-Trip Requests)** — `Tool::execute` returns
  `ToolCallOutcome` (`Complete` | `InputRequired`). `handle_tools_call` seals
  continuation state via an AES-256-GCM codec and returns `input_required`;
  retry requests are verified against principal/method/params/expiry.
- **`requestState` AEAD codec** (`AesGcmStateCodec`) — server-only, uses
  `@getrandom` (OS entropy) for key + per-seal nonce, `@mooncry` for AES-GCM.
  `RequestStateCodec` trait with `seal`/`open`; clock injected via
  `MCPServer::with_clock` for testability.
- **Spec error codes**: `HeaderMismatch` (-32020),
  `MissingRequiredClientCapability` (-32021), `UnsupportedProtocolVersion`
  (-32022) with structured `data` (`supported`, `requiredCapabilities`).
- **HTTP header validation**: `MCP-Protocol-Version`, `Mcp-Method`,
  `Mcp-Name` enforced on POST; mismatch → 400 + `HeaderMismatch`.

### Added — Client

- **Per-request `_meta`**: every request carries protocolVersion,
  clientCapabilities, clientInfo via `build_request_meta` +
  `MCPClient::request_meta`. `MCP-Method`/`Mcp-Name` headers mirrored on HTTP.
- **`MCPClient::discover`** — queries server identity/capabilities, stores
  `server_capabilities` + `server_info` (the latter newly added to the struct).
- **Transparent MRTR handling** — `call_tool`/`read_resource`/`get_prompt` go
  through `send_with_mrtr`, which detects `input_required`, fulfills inputs
  via elicitation/sampling/roots handlers, and retries with `inputResponses` +
  echoed `requestState`. Bounded to 8 rounds.
- **`src/client/legacy/`** package — standalone `LegacyClient` with the
  2025-11-25 `initialize` handshake + `send_raw`, depending only on transport
  + protocol/types (never imports the modern client). Deletable in one cut.

### Removed — Server (clean cut, breaking)

- `initialize` / `notifications/initialized` handshake.
- `ping`, `logging/setLevel` (log level now per-request `_meta.logLevel`).
- `resources/subscribe` / `resources/unsubscribe` (replaced by
  `subscriptions/listen`).
- `MCPServer.log_level` field.
- HTTP session model: `Mcp-Session-Id`, GET SSE long-poll, DELETE
  session-close, `Last-Event-ID` resumability. `HttpTransport` loses
  `session_id`/`sse_active` fields.

### Removed — Modern client (legacy moved to `src/client/legacy/`)

- `MCPClient::initialize` / `ping` / `set_log_level` / `subscribe_resource` /
  `unsubscribe_resource` and their builders. `connect_http`/`connect_stdio`
  no longer run the handshake (2026-07-28 is stateless).

### Changed

- Bumped module version `0.14.1` → `0.15.0`.
- Resource-not-found error code: `MethodNotFound` → `InvalidParams` (-32602).
- `Tool::execute` return type: `ToolResult` → `ToolCallOutcome` (breaking).
- `ReplyHandle`/`ServerRequest` made `pub(all)` to support the public
  `ActiveSubscription` type.

### Known limitations (follow-ups)

- **Era probe + ClientBackend dispatch** (MIGRATION-0.15.md §10b): the modern
  client does not yet auto-fallback to `LegacyClient` on legacy servers.
  `LegacyClient` exists in `src/client/legacy/` but is not wired into
  `connect_http`/`connect_stdio`. Modern-only deployments work today; dual-era
  support is the next step.
- **HTTP per-request SSE streaming**: `subscriptions/listen` delivers the
  acknowledgment over HTTP, but ongoing notification streaming on a single
  POST response requires per-request SSE (the transport currently returns one
  JSON body per POST). stdio fully supports ongoing streams.
- **`requestState` clock**: `MCPServer` defaults `clock` to a stub returning 0;
  production servers must inject a real clock via `with_clock` for expiry
  enforcement.

## [0.14.1] - 2026-06-18

### Fixed

- Patch release following 0.14.0 (no public changelog entry was recorded).

## [0.14.0] - 2026-06-16

### Breaking Changes

- Re-centered the public API on `MCPServer`, `MCPClient`, and `MCPHost`.
- Removed the normal user path through `MCPServer::run(AnyTransport, group)`.
- Changed `MCPServer::run_http` to own its task group: `run_http(port?, path?)`.
- Replaced direct `MCPClient::new(..., transport~)` construction with `MCPClient::connect_http` and `MCPClient::connect_stdio`.
- Moved request builders and low-level registration helpers out of the public client/server API.
- Stopped re-exporting transport types from the root package facade.

### Added

- `MCPHost` for first-class host mode with named connections.
- `MCPHost::connect_stdio`, `MCPHost::connect_http`, `MCPHost::list_tools`, `MCPHost::call_tool`, and `MCPHost::close_all`.
- Qualified host tool routing with `connection.tool` names.
- High-level server builder methods: `.tool(...)`, `.resource(...)`, and `.prompt(...)`.
- `MIGRATION-0.14.md` with server, client, host, and advanced transport migration examples.

### Runtime and Performance

- Server dispatch parses requests once and classifies by parsed method.
- Fast methods run inline; slow handler methods spawn only when they may suspend.
- STDIO output remains serialized through one response queue.
- HTTP server responses use per-request reply handles.
- Client response dispatch is centered on the runtime pending map keyed by JSON-RPC id.

### Documentation

- Rewrote quickstart, server, client, transport, architecture, and host docs for the v0.14 API.
- Updated examples to use `MCPHost` instead of hand-written host structs.

## [0.5.0] - 2026-02-05

### ⚡ Performance - 8x Boost

**JSON Serialization Optimization** (800ms → 100ms for 20 tools)
- Replaced O(N²) string concatenation with O(N) `StringBuilder` in `json_builder.mbt`
- Eliminated 40,000+ string allocations per `tools/list` request
- All JSON building functions now use `StringBuilder`: `json_string()`, `json_object()`, `json_array()`

**Schema Caching**
- Added `cached_schema_json: String` to `ToolEntry` and `ToolDefinition`
- Tool schemas are stringified once at registration, reused on every `tools/list` call
- Eliminated redundant schema serialization overhead

**Result**: `tools/list` with 20 tools: **800ms → 100ms (8x faster)**

### 🚀 Concurrent Request Handling

**Producer-Consumer Architecture**
- Server now handles multiple tool calls concurrently using `@async.TaskGroup`
- Added `@aqueue.Queue[String]` for thread-safe response queueing
- Each incoming request spawns independent handler task
- Single sender task prevents stdout write conflicts

**What Changed**:
- `MCPServer::run()` now accepts `group: @async.TaskGroup[Unit]` parameter
- `run_stdio()` automatically creates task group
- `run_http()` passes existing group parameter

**Result**: 4 concurrent tool requests now execute in parallel (cooperative multitasking) instead of serially

**Limitation**: MoonBit async is single-threaded (coroutines), not OS-thread parallelism. Ideal for I/O-bound tools (network, file operations), limited benefit for CPU-bound computation.

### 🎨 Developer Experience - SchemaBuilder API

**Fluent API for Schema Definition** (30% less code)
- New `@core.schema_builder()` fluent API for readable schema construction
- Type constructors: `str_type()`, `int_type()`, `num_type()`, `bool_type()`, `arr_type()`, `obj_type()`
- `.field(name, type, required=, desc=)` chaining
- `.build(desc=)` for final schema

**Before (10 lines)**:
```moonbit
@core.obj_schema(
  {
    "title": @core.str_schema(desc="Note title"),
    "content": @core.str_schema(desc="Note content"),
    "tags": @core.arr_schema(@core.str_schema(), desc="Tags"),
  },
  ["title", "content"],
  desc="Create note parameters"
)
```

**After (7 lines)**:
```moonbit
@core.schema_builder()
  .field("title", @core.str_type(), required=true, desc="Note title")
  .field("content", @core.str_type(), required=true, desc="Note content")
  .field("tags", @core.arr_type(@core.str_type()), desc="Tags")
  .build(desc="Create note parameters")
```

### 🧹 Removed - Clean v0.5.0 (BREAKING CHANGES)

**Deleted All Deprecated Code**:
- ❌ Removed `src/server/deprecated.mbt` (helper functions: `string_param`, `number_param`, etc.)
- ❌ Removed `src/server/schema_test.mbt` (tests using old API)
- ❌ Removed `MIGRATION-0.4.md` (obsolete migration guide)

**Removed APIs**:
- `@mcp.string_param()`, `@mcp.number_param()`, `@mcp.boolean_param()`
- `@mcp.optional_*_param()` helpers
- `MCPServer::new()` - use `@mcp.mcp_server(name~, version~)` instead
- `server.register_trait_tool()` - use `server.with_tool()` instead
- `server.run(transport)` - use `server.run_stdio()` or `server.run_http()` instead

### Added

- **SchemaBuilder API**:
  - New `src/core/schema_builder.mbt` with fluent schema construction
  - `SchemaType` enum: `Str`, `Int`, `Num`, `Bool`, `Arr(SchemaType)`, `Obj`
  - `SchemaBuilder` struct with `.field()` and `.build()` methods
  - Type constructors: `str_type()`, `int_type()`, `num_type()`, `bool_type()`, `arr_type()`, `obj_type()`

- **Performance Infrastructure**:
  - `StringBuilder` optimization in `src/internal/json_builder.mbt`
  - Schema caching in `src/server/registry.mbt`
  - Cached schema field in `src/types/protocol.mbt`

- **Concurrent Execution**:
  - `@async.TaskGroup` support in `MCPServer::run()`
  - `@aqueue.Queue` for response queueing
  - Background sender task for thread-safe output
  - Added `moonbitlang/async/aqueue` dependency to `src/server/moon.pkg`

- **Documentation**:
  - New `MIGRATION-0.5.md` comprehensive migration guide from 0.3.x/0.4.x to 0.5.0
  - Complete examples of old vs new code
  - API change reference table
  - Troubleshooting section

### Changed

- **Server API** (BREAKING):
  - `MCPServer::run()` signature: `run(transport)` → `run(transport, group: @async.TaskGroup[Unit])`
  - `run_stdio()` now creates task group internally
  - `run_http()` passes group parameter to `run()`
  
- **Internal Architecture**:
  - Request handling: Serial loop → Concurrent task spawning
  - Response sending: Direct write → Queue-based sender task
  - JSON building: String concatenation → StringBuilder
  - Schema serialization: Per-request → Cached at registration

- **ToolEntry Structure**:
  - Added `cached_schema_json: String` field

- **ToolDefinition Structure**:
  - Added `cached_schema_json: String` field

### Fixed

- `expand_params_to_json()` function moved from `deprecated.mbt` to `tool_bridge.mbt` (was inaccessible after deprecation removal)
- `ToolResult` references updated to use `@tool.ToolResult::` namespace in tests
- `EchoTool` in tests updated to use direct `ParamDef` construction (removed dependency on deprecated helpers)

### Performance

- **tools/list endpoint**: 800ms → 100ms (8x faster) for 20 tools
- **Concurrent requests**: 4 requests now execute in parallel vs serial execution
- **Memory**: Eliminated ~40,000 string allocations per `tools/list` call
- **Schema serialization**: Once at registration vs every request

### Migration Guide

See [MIGRATION-0.5.md](MIGRATION-0.5.md) for comprehensive upgrade instructions from 0.3.x/0.4.x.

**Quick Summary**:
1. Update server creation: `MCPServer::new()` → `@mcp.mcp_server(name~, version~)`
2. Update tool registration: `.register_trait_tool()` → `.with_tool()`
3. Update server run: `.run(transport)` → `.run_stdio()` or `.run_http(port)`
4. Replace param helpers with direct `ParamDef` construction or use SchemaBuilder
5. Remove any `@mcp.string_param()` etc. calls - use `ParamDef::{ name, schema, required }`

### Testing

- ✅ All 76 tests passing (100% coverage)
- ✅ `moon check`: 0 errors (9 unused_field warnings - safe to ignore)
- ✅ `moon build`: Success
- ✅ `moon fmt`: All code formatted

## [0.3.0] - 2026-01-25

### Added
- **Resources API**: Full MCP Resources primitive implementation
  - `Resource` trait for defining resources
  - `server.register_trait_resource()` for registration
  - Support for list, read, subscribe, unsubscribe operations
  - O(1) URI lookup via Map-based registry
- **Prompts API**: Full MCP Prompts primitive implementation
  - `Prompt` trait for defining prompt templates
  - `server.register_trait_prompt()` for registration
  - Support for list and get operations with dynamic arguments
  - PromptArgument, PromptMessage, GetPromptResult types
- **Notifications**: Server-initiated notifications
  - `server.notify_tools_list_changed()` method
  - `server.notify_resources_list_changed()` method
  - `server.notify_prompts_list_changed()` method
  - SSE streaming for HTTP transport notifications
- **Performance**: ToolRegistry optimization
  - Converted from Array (O(n)) to Map (O(1)) lookup
  - Cached tools_list for O(1) list operations
  - Significant performance improvement for servers with many tools
- **Documentation**:
  - Comprehensive README updates with Resources and Prompts examples
  - MIGRATION.md guide for upgrading from v0.2.1
  - docs/PERFORMANCE.md with optimization details
  - docs/SECURITY.md with security best practices
- **Examples**:
  - Knowledge Base Assistant example demonstrating all 3 primitives

### Changed
- Internal ToolRegistry implementation (Array → Map) for better performance
- Updated test suite to 90 tests (was 87)

### Fixed
- HTTP transport SSE implementation now properly streams notifications
- Transport error type consistency

### Performance
- Tool lookup: O(n) → O(1)
- Tool list: O(n) map operation → O(1) cached return
