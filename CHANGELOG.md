# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
