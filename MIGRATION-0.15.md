# Migration Guide: 0.14.x to 0.15.0

v0.15 targets the **MCP `2026-07-28` specification** — the stateless revision
that removes `initialize`/sessions and replaces server-initiated requests with
Multi Round-Trip Requests (MRTR).

This release follows an **asymmetric strategy**, driven by the observation that
nearly all popular MCP servers in the wild still speak `2025-11-25`:

| Component | Protocol | Legacy support | Strategy |
|---|---|---|---|
| **`MCPServer`** | `2026-07-28` only | **none** | Clean rewrite. Breaking changes accepted. |
| **`MCPClient`** | `2026-07-28` first | `2025-11-25` fallback | Modern is the main code path. Legacy lives in an isolated package. **Probe modern first, fall back to legacy on detection.** |

The legacy client code is structured so that when the ecosystem has migrated,
it can be deleted in one cut (one directory + one fallback branch).

---

## Spec Delta: what changed in 2026-07-28

Authoritative: <https://modelcontextprotocol.io/specification/2026-07-28/changelog>

### A. Statelessness — the core change

- **`initialize` / `notifications/initialized` handshake removed.** ([SEP-2575][s2575])
- **Protocol-level sessions removed.** `Mcp-Session-Id` gone from Streamable HTTP.
- **Every request is self-contained.** Protocol version + identity + capabilities
  ride in `_meta` on each request:
  - `io.modelcontextprotocol/protocolVersion` *(required)*
  - `io.modelcontextprotocol/clientCapabilities` *(required)*
  - `io.modelcontextprotocol/clientInfo` *(recommended)*
  - `io.modelcontextprotocol/logLevel` *(optional, replaces `logging/setLevel`)*
- **Every result is self-contained.** Servers SHOULD include
  `io.modelcontextprotocol/serverInfo` in each result's `_meta`.
- Mismatches rejected: `UnsupportedProtocolVersionError` (`-32022`),
  `MissingRequiredClientCapabilityError` (`-32021`).

> Refs: [basic/index `_meta`](https://modelcontextprotocol.io/specification/2026-07-28/basic/index#meta),
> [versioning](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning)

### B. Streamable HTTP transport

- **GET stream endpoint removed.** No standalone server-initiated SSE stream.
- **SSE resumability removed.** `Last-Event-ID` and event IDs gone. A broken
  response stream loses the in-flight request; re-issue with a new id.
- **DELETE (session end) removed.** Answer GET/DELETE on the MCP endpoint with
  `405 Method Not Allowed`.
- **Per-request SSE responses.** Each POST answered with either a single JSON
  object *or* an SSE stream scoped to that request (progress notifications then
  the final response).
- **New required headers** on every POST, mirrored from the body:
  - `MCP-Protocol-Version` *(required)*
  - `Mcp-Method` *(required for all requests)*
  - `Mcp-Name` *(required for `tools/call`, `resources/read`, `prompts/get`)*
- **`x-mcp-header` / `Mcp-Param-{Name}`** optional parameter-mirroring mechanism.
  Clients MUST support it. ([SEP-2243][s2243])
- **Server-side header validation** rejects mismatches with `HeaderMismatch`
  (`-32020`), HTTP `400`.
- `X-Accel-Buffering: no` SHOULD be sent on SSE responses.

> Refs: [streamable-http](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)

### C. stdio transport

- Wire format unchanged. No session/handshake on the wire.
- **`notifications/cancelled` is now stdio-only.** On HTTP, closing the SSE
  response stream *is* the cancellation signal.
- **Dual-era client probe**: send `server/discover` first; fall back to
  `initialize` only on a non-modern error or timeout.
- Shutdown semantics unchanged (close stdin → prompt exit).

> Refs: [stdio](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio)

### D. New & removed RPC methods

| Status | Method | Notes |
|---|---|---|
| **NEW** | `server/discover` | Servers MUST implement. Returns `supportedVersions`, `capabilities`, `serverInfo`, `instructions`, `ttlMs`, `cacheScope`. Optional for clients; the natural probe for legacy fallback. |
| **NEW** | `subscriptions/listen` | Replaces `resources/subscribe` + `resources/unsubscribe` + the GET stream. Long-lived POST-response SSE stream with opt-in filter (`toolsListChanged` / `promptsListChanged` / `resourcesListChanged` / `resourceSubscriptions`). Server MUST send `notifications/subscriptions/acknowledged` first, tagged with `io.modelcontextprotocol/subscriptionId` = the listen request's JSON-RPC id. |
| **REMOVED** | `initialize` / `notifications/initialized` | Gone (modern path). Legacy pkg keeps them. |
| **REMOVED** | `ping` | Statelessness makes it pointless. |
| **REMOVED** | `logging/setLevel` | Per-request `_meta.io.modelcontextprotocol/logLevel`. |
| **REMOVED** | `resources/subscribe` / `resources/unsubscribe` | Replaced by `subscriptions/listen`. |
| **REMOVED** | `notifications/roots/list_changed` | Roots feature deprecated. |
| **REMOVED** | `notifications/elicitation/complete` | MRTR replaces it. |

> Refs: [server/discover](https://modelcontextprotocol.io/specification/2026-07-28/server/discover),
> [subscriptions](https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/subscriptions)

### E. Multi Round-Trip Requests (MRTR)

The biggest semantic shift. Servers **MUST NOT** send `sampling/createMessage`,
`roots/list`, or `elicitation/create` as independent requests anymore. ([SEP-2322][s2322])

- On a supported client request (`tools/call`, `resources/read`, `prompts/get`),
  the server returns a result with:
  - `resultType: "input_required"`
  - `inputRequests`: `{ <server-key>: { method, params } }` — one of the three
    input request types
  - `requestState`: opaque server-owned blob
- Client fulfills inputs, retries the original request (new JSON-RPC id) with
  `inputResponses` (same keys) + echoed `requestState`.
- **Every result now carries `resultType`**: `"complete"` or `"input_required"`.
  Absent ⇒ `"complete"` (back-compat with older servers).

**`requestState` security requirements (normative):**

- Treat as attacker-controlled on receipt.
- If it influences authorization/resource access/business logic, **MUST** apply
  integrity protection (HMAC **or** AEAD) and **MUST** reject on verification
  failure. Integrity MAY be omitted only when tampering can cause nothing worse
  than request failure.
- To prevent replay, SHOULD include inside the protected payload:
  - the authenticated principal
  - a short TTL/expiry
  - a request identifier (method name + digest of salient params)
- Single-use invariants (one-time redemptions) MUST be enforced server-side —
  the blob alone does not guarantee single-use.

> Refs: [mrtr](https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr)

### F. Cacheable results

`tools/list`, `prompts/list`, `resources/list`, `resources/read`,
`resources/templates/list`, `server/discover` carry **`ttlMs`** + **`cacheScope`**
(`"public"` / `"private"`). ([SEP-2549][s2549])

### G. Error codes

| Code | Name | Notes |
|---|---|---|
| `-32000`–`-32019` | legacy range | No new allocations. |
| `-32020` | `HeaderMismatch` | *(new)* header/body mismatch. |
| `-32021` | `MissingRequiredClientCapability` | *(new)*. |
| `-32022` | `UnsupportedProtocolVersion` | *(new)* `data.supported` lists versions. |
| `-32602` | Invalid Params | Now used for resource-not-found (was `-32002`). |

### H. Schema & misc

- **JSON Schema 2020-12** default dialect; no auto-deref of network `$ref`. ([SEP-2106][s2106])
- `extensions` field on capabilities for negotiating extensions.
- Servers SHOULD return `tools/list` in deterministic order (prompt-cache hit).
- **Deprecated** (still work, don't build new): Roots, Sampling, Logging
  features; HTTP+SSE transport. ([SEP-2577][s2577])

[s2575]: https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2575
[s2243]: https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2243
[s2322]: https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2322
[s2549]: https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2549
[s2106]: https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2106
[s2577]: https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2577

---

## Package layout for 0.15

```
src/
├── protocol/                 # shared types (RequestId, JsonRpc*, ContentItem, …)
│   └── types/                #   unchanged surface, +modern result/error types
├── transport/                # transport abstraction + modern implementations
│   ├── transport.mbt         #   trait Transport (unchanged, connection-less)
│   ├── stdio.mbt             #   server stdio        (unchanged)
│   ├── stdio_client.mbt      #   client stdio        (unchanged wire)
│   ├── http_server.mbt       #   modern 2026-07-28   (no session/GET/DELETE)
│   ├── http_client.mbt       #   modern 2026-07-28   (per-request _meta, headers)
│   └── unimplemented.mbt     #   wasm-gc stubs
├── server/                   # MCPServer — 2026-07-28 ONLY, no legacy
│   ├── server.mbt            #   +server/discover, +subscriptions/listen routes
│   ├── handler.mbt           #   −handle_initialize, −handle_ping, −setLevel,
│   │                         #   −subscribe/unsubscribe; +handle_discover,
│   │                         #   +handle_subscriptions_listen; MRTR-aware
│   ├── request_state.mbt     #   NEW: AEAD requestState codec (§Crypto)
│   │                         #   uses @getrandom + @mooncry (server-only)
│   ├── registry.mbt / *_bridge.mbt / *_registry.mbt  (mostly unchanged)
├── client/                   # MCPClient — modern main path
│   ├── client.mbt            #   −initialize; +per-request _meta; era probe
│   ├── request_builder.mbt   #   −initialize builders; +discover/listen/_meta
│   ├── notification_handler.mbt
│   ├── host.mbt              #   delegates, era-agnostic
│   ├── client_types.mbt
│   └── legacy/               # ← THE LEGACY BOUNDARY (see below)
│       ├── moon.pkg.json     #   depends only on transport + protocol
│       ├── legacy_client.mbt #   LegacyClient: owns initialize handshake
│       ├── legacy_builder.mbt#   build_initialize_request, initialized notif
│       └── legacy_handler.mbt#   parse initialize response, session handling
└── top.mbt
```

### Crypto boundary — server only

**`@getrandom` (OS entropy) and `@mooncry` (crypto) are server-only
dependencies.** Neither may be imported by `src/client/`,
`src/client/legacy/`, or `src/transport/`. This is both a correctness rule and
a policy rule:

- **Correctness**: the protocol makes `requestState` opaque to clients. Per
  spec, clients MUST echo it verbatim and MUST NOT inspect/modify it. The
  AES-GCM seal/open, the key, and the nonce therefore live entirely inside the
  server process; a client never performs a crypto operation on `requestState`.
- **Policy**: any OS-entropy access from a client (or any crypto/FFI for
  `requestState`) is forbidden by project policy. Clients are pure protocol
  peers — they take bytes in and put bytes out.

Enforcement: `src/client/moon.pkg.json` and `src/client/legacy/moon.pkg.json`
list **no** `@getrandom` / `@mooncry` dependencies. Only
`src/server/moon.pkg.json` adds them. This is reviewable from the package
graphs alone — a client PR that adds such a dep should fail review.

### The legacy boundary (`src/client/legacy/`)

**Goal**: when the ecosystem has migrated, deleting `src/client/legacy/` and
removing one `match` arm in the connect path is the entire removal.

Rules for the boundary:

- **`src/client/legacy/` has its own `moon.pkg.json`** depending only on
  `colmugx/mcp/transport` and `colmugx/mcp/protocol/types`. It does **not**
  import `colmugx/mcp/client` (no circular dependency).
- **`LegacyClient`** wraps a raw transport and owns the `initialize` handshake,
  `notifications/initialized`, and session header management. Its public surface
  mirrors just what `MCPClient` needs to delegate: `connect`, `send_request`,
  `close`.
- **The main `MCPClient` does not import legacy types in its public API.** The
  fallback is an internal implementation detail. `MCPClient` holds an
  `enum ClientBackend { Modern(ModernCore); Legacy(LegacyClient) }` and
  dispatches through it.
- **`MCPHost` is era-agnostic**: it talks to `MCPClient`, which hides the era.
  No host changes for legacy support.

> Note: the modern HTTP transport drops session support entirely. The legacy
> fallback therefore needs the *old* session-capable HTTP client. Cleanest is
> to keep a session-capable transport inside the legacy pkg itself
> (`legacy/http_session.mbt`), so the modern `transport/http_client.mbt` stays
> pure. The legacy pkg owns its own transport bits.

---

## Implementation checklist

Tasks grouped; each references the spec section and the current code location.
Within a group, items are roughly independent.

### 0. Housekeeping

- [ ] **0.1** Bump `moon.mod` version `0.14.1` → `0.15.0`.
- [ ] **0.2** Crypto deps already in `moon.mod`: `cc06b/mooncry@0.13.1` and
  `Tigls/mb-getrandom@0.1.0`. Add them to **`src/server/moon.pkg.json` only**
  — never to `src/client/`, `src/client/legacy/`, or `src/transport/`
  (see *Crypto boundary*). `@getrandom` provides OS entropy (key + nonce),
  `@mooncry` provides AES-GCM.
- [ ] **0.3** Introduce a single protocol-version constant
  `const ProtocolVersion = "2026-07-28"` in `src/protocol/types/protocol.mbt`.
  Replace hardcoded `"2025-11-25"` in modern code paths:
  - `src/transport/http_client.mbt:17,41`
  - `src/transport/http_server.mbt:234,252,270`
  - (the two in `handler.mbt:77` and `request_builder.mbt:31` die with the
    initialize code — see 2.x and 7.x)
- [ ] **0.4** Update stale `2025-06-18` comments:
  `notification.mbt:3`, `prompt/prompt.mbt:3`, `resource/resource.mbt:3`.
- [ ] **0.5** CHANGELOG entries for `0.14.1` (missing) and `0.15.0`.

### 1. Server: remove initialize & legacy methods *(spec A, D)* — clean cut

`MCPServer` has no legacy path. Delete outright.

- [ ] **1.1** Delete `handle_initialize` (`src/server/handler.mbt:54-85`).
- [ ] **1.2** Delete the `"initialize"` route branch
  (`src/server/server.mbt:169`) and remove `"initialize"` from `is_fast_method`
  (`:156`).
- [ ] **1.3** Delete `handle_ping` (`handler.mbt:49`) + its route + client
  `MCPClient::ping` (`client.mbt:363`) + `build_ping_request`
  (`request_builder.mbt:50`). *(ping still exists on the legacy client for
  talking to legacy servers — but it's not in the modern server. Decide: keep
  `ping` as a client-only legacy-compat helper inside `legacy/`, or drop it.)*
- [ ] **1.4** Delete `logging/setLevel`: server `handle_set_level`
  (`handler.mbt:336`) + route + client `set_log_level` (`client.mbt:373`) +
  `build_set_log_level_request`. Log level rides per-request `_meta.logLevel`.
- [ ] **1.5** Delete `resources/subscribe` / `resources/unsubscribe`:
  handlers (`handler.mbt:229-260`) + routes + client methods
  (`client.mbt:386,399`) + builders. Replaced by `subscriptions/listen` (see 5.x).

### 2. Per-request `_meta` *(spec A)* — modern path, both client & server

- [ ] **2.1** Add a central meta builder in `src/client/request_builder.mbt`:
  ```moonbit
  fn build_meta(
    client_name : String,
    client_version : String,
    caps : ClientCapabilities,
    log_level~ : String? = None,
  ) -> Json
  ```
  producing
  `{ protocolVersion, clientInfo, clientCapabilities, logLevel? }` under the
  `io.modelcontextprotocol/*` keys.
- [ ] **2.2** Thread `_meta` into **every** modern request builder
  (`tools/list`, `tools/call`, `resources/list|read|templates_list`,
  `prompts/list|get`, `completion/complete`, `server/discover`,
  `subscriptions/listen`). `_meta` is a field of `params`.
- [ ] **2.3** Server side: inject `io.modelcontextprotocol/serverInfo` into
  every result's `_meta`. Cleanest is to extend `jsonrpc_success_str`
  (`handler.mbt:12`) to accept the `MCPServer` identity and emit `_meta`
  centrally — keeps per-handler code unchanged.
- [ ] **2.4** Client: store `serverInfo` on first response (currently
  `initialize` read it at `client.mbt:222-249` but never stored it). Move to
  the `discover()` result or first-response path. `MCPClient.server_capabilities`
  field (`client.mbt:24`) is also currently never written — fix that too.

### 3. Server: `server/discover` *(spec D)*

- [ ] **3.1** Add `handle_discover` in `handler.mbt` returning:
  ```json
  { "resultType": "complete",
    "supportedVersions": ["2026-07-28"],
    "capabilities": { ... },
    "_meta": { "io.modelcontextprotocol/serverInfo": {...} },
    "instructions": <server.instructions>?,
    "ttlMs": <ms>, "cacheScope": "public" }
  ```
- [ ] **3.2** Register the route in `server.mbt` (`handle_parsed_request`
  match) and add `"server/discover"` to `is_fast_method` (it's a cheap read).

### 4. Server: `subscriptions/listen` *(spec D)* — the big new server feature

Long-lived request whose response is an open SSE stream (HTTP) or a tagged
notification sub-channel (stdio).

- [ ] **4.1** Add `handle_subscriptions_listen` (NOT a fast method — spawn as
  background task holding the stream open). Parse the `notifications` filter:
  `toolsListChanged` / `promptsListChanged` / `resourcesListChanged` /
  `resourceSubscriptions: [uri]`.
- [ ] **4.2** First message out MUST be
  `notifications/subscriptions/acknowledged` carrying
  `io.modelcontextprotocol/subscriptionId` = the listen request's JSON-RPC id,
  plus the agreed filter subset.
- [ ] **4.3** Stream: emit matching notifications (`tools/list_changed`,
  `resources/updated`, …), each tagged with the same `subscriptionId` in
  `_meta`. On stdio, all subscriptions share one channel — clients demux by id.
- [ ] **4.4** Graceful close: respond to the original listen request with an
  empty result (carrying `subscriptionId`), then close.
- [ ] **4.5** Rework `ResourceRegistry.subscriptions`
  (`resource_registry.mbt:15`) from a per-connection `Array[String]` to a
  **per-`subscriptionId`** map: `Map[RequestId, SubscriptionFilter]`. The
  existing `subscribe`/`unsubscribe` methods (`:70,87`) become internal helpers
  driven by listen/cancel.

### 5. Server: MRTR + `requestState` *(spec E)* — see §Crypto for the codec

- [ ] **5.1** Extend the result builder to emit `resultType`: every success
  path produces `"resultType": "complete"`; the new input-required path
  produces `"input_required"`.
- [ ] **5.2** Give `tools/call`, `resources/read`, `prompts/get` handlers
  (`handler.mbt:101,194,300`) the ability to return `InputRequiredResult`
  instead of a normal result. They become able to suspend, request input, and
  resume on retry. Handler return type changes from `String` to a small enum
  `HandlerOutcome { Complete(String); InputRequired(InputRequests, state~) }`.
- [ ] **5.3** On retry, those handlers read `inputResponses` + `requestState`
  from params; the codec (`request_state.mbt`) opens and verifies `requestState`.
- [ ] **5.4** Server MUST NOT include `elicitation/create` in `inputRequests`
  if the client didn't declare the elicitation capability (read from the
  request's `_meta.clientCapabilities`). Same for sampling/roots.

### 6. Client: MRTR handling *(spec E)*

- [ ] **6.1** Replace `handle_server_request` (`client.mbt:561`) and the
  `on_sampling`/`on_roots`/`on_elicitation` inbound-request model with an
  `InputRequiredResult` *response* handler. When a `tools/call` etc. response
  has `resultType: "input_required"`:
  1. parse `inputRequests`
  2. invoke the user's sampling/roots/elicitation callbacks → build
     `inputResponses`
  3. retry the original request with a **new** JSON-RPC id, carrying
     `inputResponses` + the echoed `requestState` verbatim.
- [ ] **6.2** All result parsers must read `resultType`; absent ⇒ `"complete"`
  (back-compat with `2025-11-25` servers — relevant because the legacy fallback
  will produce `resultType`-less results).

### 7. Streamable HTTP — server transport *(spec B)*

`src/transport/http_server.mbt` — `HttpTransport`.

- [ ] **7.1** Delete session state: `session_id` field (`:50`), constructor
  init (`:66`), first-request creation (`:210-213`), header read (`:215-218`),
  `Mcp-Session-Id` response headers (`:232-236`, `:253`).
- [ ] **7.2** **Remove the GET handler** (`:246-264`); answer GET on the MCP
  endpoint with `405 Method Not Allowed`.
- [ ] **7.3** **Remove the DELETE handler** (`:265-273`); answer `405`.
- [ ] **7.4** **Per-request SSE responses**: a POST may be answered with
  `text/event-stream` carrying progress notifications then the final response.
  Add an SSE-emission path alongside the single-body POST response
  (`receive_request`/`send`, `:285-334`). Send `X-Accel-Buffering: no` on SSE.
- [ ] **7.5** **Header validation**:
  - require `MCP-Protocol-Version`, `Mcp-Method`, and `Mcp-Name` (for the
    relevant methods); reject mismatch with `400` + `HeaderMismatch` (`-32020`).
    Compare Base64-sentinel values after decoding.
  - cross-check `MCP-Protocol-Version` against body's `protocolVersion`;
    mismatch → `400`.
  - unknown version → `400` + `UnsupportedProtocolVersionError` (`-32022`)
    with `data.supported`.
  - unknown method → `404` + JSON-RPC `-32601`.
- [ ] **7.6** Keep the by-id response dispatch (`pending_reply_queues`,
  `id_key_from_json`) — session-independent, still needed.

### 8. Streamable HTTP — client transport (modern) *(spec B)*

`src/transport/http_client.mbt` — `HttpClientTransport`.

- [ ] **8.1** Delete session fields: `session_id` (`:8`), `last_event_id`
  (`:14`), SSE replay buffers if replay-only (`:15-16`).
- [ ] **8.2** Stop sending/reading `Mcp-Session-Id`: `establish_sse` (`:54-58`),
  POST send (`:145-149`), response extraction (`:178-182`), `send_notification`
  (`:316-319`). Delete the `404 → "session expired, re-initialize"` branch
  (`:184-190`); replace with stateless "transient failure, surface to caller".
- [ ] **8.3** Delete `close_session` (`:361-392`) and its call in `close`
  (`:403`); sync the wasm-gc stub `unimplemented.mbt:261-265`.
- [ ] **8.4** **Add required POST headers** on every send:
  `MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name` (for the three name-bearing
  methods). `Accept: application/json, text/event-stream` should already hold.
- [ ] **8.5** Implement `x-mcp-header` mirroring: when calling `tools/call`,
  inspect the cached `inputSchema` for `x-mcp-header` annotations at
  statically-reachable property paths; extract the arg value; emit
  `Mcp-Param-{Name}` with value encoding (Base64 sentinel `=?base64?...?=`
  when non-ASCII / control / leading-trailing whitespace / matches sentinel).
- [ ] **8.6** Accept both `application/json` and `text/event-stream` POST
  responses; route both into the id-keyed pending queue.
- [ ] **8.7** On `400 Bad Request` with a recognized modern JSON-RPC error body
  (`UnsupportedProtocolVersion` / `MissingRequiredClientCapability` /
  `HeaderMismatch`): do NOT fall back to legacy here — these mean the server is
  modern. Surface the error. *(The era probe in §10 handles fallback.)*

### 9. stdio transport *(spec C)* — minimal

- [ ] **9.1** `StdioTransport` / `StdioClientTransport` need **no protocol
  changes**. Confirmed: `stdio.mbt:5`, `stdio_client.mbt:17` have no
  session/handshake.
- [ ] **9.2** Document that `notifications/cancelled` is now stdio-only (the
  existing `parse_cancelled_notification` at `notification_handler.mbt:110` is
  fine).
- [ ] **9.3** Unexpected-exit handling: spec says "because the protocol is
  stateless, in-flight requests are lost; client retries against fresh process;
  active `subscriptions/listen` streams must be re-established." Document this
  in the client restart path.

### 10. Client: era probe + legacy fallback *(spec C, versioning)*

This is the heart of the asymmetric strategy. The connect path becomes:

```
connect_http / connect_stdio
  └─ try modern:
       1. open transport
       2. server/discover (probes era + discovers versions/caps)
       3. on Ok(DiscoverResult): use ModernClient backend
       4. on Ok modern error (UnsupportedProtocolVersion, …): retry with a
          supported version; stay modern
       5. on non-modern error / timeout: fall through to legacy
  └─ fallback legacy:
       1. construct LegacyClient (src/client/legacy/)
       2. LegacyClient.initialize() handshake
       3. use LegacyClient backend
```

- [ ] **10.1** Introduce the backend enum in `client.mbt`:
  ```moonbit
  priv enum ClientBackend {
    Modern(ModernCore)
    Legacy(@legacy.LegacyClient)
  }
  ```
  `MCPClient` holds one; all public methods dispatch through it.
- [ ] **10.2** Implement the probe in `connect_http` (`client.mbt:63`) and
  `connect_stdio` (`:80`). Replace the current unconditional `client.initialize()`
  call (`:73,99`) with the probe. Cache the era for the connection's lifetime
  (per spec: per server-process for stdio, per origin for HTTP).
- [ ] **10.3** Build `src/client/legacy/`:
  - `moon.pkg.json` — deps: `colmugx/mcp/transport`, `colmugx/mcp/protocol/types`
    only.
  - `legacy_client.mbt` — `LegacyClient` struct + `initialize()` handshake.
  - `legacy_builder.mbt` — move `build_initialize_request` +
    `build_initialized_notification` here (from `request_builder.mbt:2-47`).
  - `legacy_handler.mbt` — parse initialize response, extract `serverInfo` /
    `protocolVersion` / `capabilities`.
  - `http_session.mbt` — session-capable HTTP client transport (the modern
    `http_client.mbt` drops session support; legacy needs it). This is the
    only place `Mcp-Session-Id` / `Last-Event-ID` / DELETE-close logic lives.
- [ ] **10.4** `MCPHost` (`host.mbt`) needs **no** legacy awareness — it calls
  `MCPClient`, which hides the era. Confirm `connect_http`/`connect_stdio`
  delegates (`host.mbt:16,38`) still work after the probe is added.

### 11. Error codes *(spec G)*

`src/protocol/types/error.mbt`.

- [ ] **11.1** Add three codes to `MCPError`:
  `HeaderMismatch(-32020)`, `MissingRequiredClientCapability(-32021)`,
  `UnsupportedProtocolVersion(-32022)` (with `data.supported`).
- [ ] **11.2** Change resource-not-found from `-32002` to `-32602` in
  `resources/read` error paths; keep accepting `-32002` from legacy servers
  (relevant for the fallback path).

### 12. Cacheable results *(spec F)*

- [ ] **12.1** Add `ttlMs` + `cacheScope` to server results for `tools/list`,
  `prompts/list`, `resources/list`, `resources/read`, `resources/templates/list`,
  `server/discover`. Cleanest: extend `jsonrpc_success_str` (`handler.mbt:12`)
  with optional cache fields.
- [ ] **12.2** (Optional, client) honor `ttlMs` as a freshness hint in list
  result caching.

### 13. Tests & docs

- [ ] **13.1** Update `src/transport/http_compliance_test.mbt` and
  `src/server/compliance_wbtest.mbt` for new headers and removed
  session/GET/DELETE.
- [ ] **13.2** Snapshot tests for `server/discover`, `subscriptions/listen`
  (incl. acknowledgment + tagged notification + graceful close), and a full
  MRTR round-trip (input_required → inputResponses → complete).
- [ ] **13.3** `requestState` crypto tests: tamper detection, expiry, principal
  mismatch, replay-window. Use known-answer vectors where possible.
- [ ] **13.4** Era-probe tests: modern server, legacy server, unsupported
  version, silent/timeout → fallback.
- [ ] **13.5** Update `examples/server` and `examples/client`
  (`examples/*/cmd/main/main.mbt`) — server is modern-only; client should
  exercise both modern and legacy peers.
- [ ] **13.6** Update `docs/` server/client/host guides.
- [ ] **13.7** `moon info && moon fmt`, review `.mbti` diffs. This release
  WILL change the public interface.

---

## Crypto: `requestState` codec

**Decision: AEAD (AES-256-GCM)** via `@mooncry`, with a pluggable trait so a
plain HMAC mode can be added later for stateless deployments that don't need
confidentiality.

### Why AEAD over plain HMAC

The spec allows either. AEAD (AES-GCM) gives **both** integrity and
confidentiality — the client cannot read the state blob, only echo it. HMAC
alone leaves the payload as visible base64 JSON. For a general-purpose SDK,
defaulting to confidential state is safer (state may include partial authz
context, user identifiers, etc.) and the cost is one mooncake we already have.

### The `RequestStateCodec` trait

New file `src/server/request_state.mbt`:

```moonbit
///|
/// Seals server-side MRTR state into the opaque `requestState` string the
/// client echoes on retry, and opens/verifies it on the retry request.
/// Implementations MUST be authenticated (HMAC or AEAD) per spec.
pub trait RequestStateCodec {
  /// Serialize + protect. Output is a transport-safe string (base64url).
  seal(Self, payload : RequestStatePayload) -> String

  /// Verify + deserialize. Returns None on any integrity failure, expiry,
  /// principal mismatch, or request-id mismatch.
  open(Self, blob : String, expected : RequestStateContext) -> RequestStatePayload?
}

///|
/// What the server puts inside the protected blob.
pub(all) struct RequestStatePayload {
  principal : String?        // authenticated user; None if anonymous
  expires_at : Int           // unix seconds; reject if now > expires_at
  request_method : String    // e.g. "tools/call"
  params_digest : String     // hex sha256 of salient params (see below)
  state : Json               // server's own opaque continuation state
}

///|
/// Context checked on open (computed from the incoming retry request).
pub(all) struct RequestStateContext {
  principal : String?
  request_method : String
  params : Json               // re-hashed to compare against params_digest
}
```

`params_digest` = `sha256(canonical_json(params)).hex()`. Canonical JSON =
keys sorted, no insignificant whitespace. This binds the blob to the retry
request, satisfying the spec's "method name and a digest of salient parameters"
SHOULD.

### Default implementation: `AesGcmStateCodec`

```moonbit
///|
pub struct AesGcmStateCodec {
  key : Bytes          // 32 bytes (AES-256), from @getrandom at startup
}
```

The codec holds no RNG state — each `seal` draws a fresh nonce directly from
`@getrandom.getrandom(12)`. No counter, no DRBG, no synchronization.

**Format of the sealed string** (base64url of):

```
[ 12-byte nonce ][ ciphertext ][ 16-byte GCM tag ]
```

- **AAD (additional authenticated data)**: a fixed domain-separation constant
  like `b"mcp-requeststate-v1"`. Binds the ciphertext to this purpose without
  being encrypted.
- **`seal`**: nonce = `@getrandom.getrandom(12)` (fresh OS entropy per call;
  see *CSPRNG* below). Encrypt `canonical_json(payload)` with
  `@mooncry.aes_gcm_encrypt(plaintext, key, nonce, aad) -> (ct, tag)`.
  Concatenate `nonce || ct || tag`, base64url-encode.
- **`open`**: base64url-decode, split (last 16 = tag, first 12 = nonce, middle
  = ct). `@mooncry.aes_gcm_decrypt(ct, key, nonce, aad, tag) -> (pt, ok)`. If
  `ok == false` → `None`. Decrypt → parse JSON → `RequestStatePayload`. Then
  check `expires_at`, `principal == expected.principal`, and
  `sha256(canonical_json(expected.params)).hex() == payload.params_digest`. Any
  failure → `None`.

**mooncry API used** (verified present):
- `@mooncry.aes_gcm_encrypt(plaintext : Bytes, key : Bytes, iv : Bytes, aad : Bytes) -> (Bytes, Bytes)`
  at `.mooncakes/cc06b/mooncry/lib/crypto.mbt:888` — returns `(ciphertext, tag)`.
- `@mooncry.aes_gcm_decrypt(ciphertext, key, iv, aad, tag) -> (Bytes, Bool)`
  at `:957` — in-tag verification.
- `@mooncry.sha256(data : Bytes) -> Bytes` at `:199`.
- `@mooncry.bytes_to_hex` / `@mooncry.hex_to_bytes` at `:49,78`.
- base64: `@mooncry` has `base64.mbt`; prefer base64url (no padding) for
  transport-safety. Confirm the exact url-safe fn name during implementation.

### What's needed from the server author

- **Key provisioning**: the server generates a 32-byte AES-256 key at startup
  via `@getrandom.getrandom(32)` (see *CSPRNG* below — server-only). For
  multi-instance deployments sharing MRTR state, distribute the key to all
  instances (otherwise a retry hitting a different instance fails to open);
  each instance can also derive its own key if state is instance-local.
- **Nonce source**: `@getrandom.getrandom(12)` per `seal`, real random nonces
  — see *CSPRNG* below. No client-side crypto involved.
- **Principal binding**: if the server authenticates clients, `principal` in
  the payload MUST be the authenticated identity, and `open` MUST reject a
  mismatched principal on retry. Without this, user A's state blob could be
  replayed by user B.
- **Single-use** (if needed): the codec does NOT enforce single-use. Servers
  that need one-time redemption (e.g. "confirm this destructive action once")
  MUST keep a consumed-ids set server-side and check it.

### CSPRNG: `mb-getrandom` (OS entropy) + `mooncry` (crypto)

AES-GCM needs a unique 96-bit nonce per message under the same key, and the
key itself must come from high-quality entropy. Two complementary mooncakes
cover this (both server-only for `requestState` purposes):

| Mooncake | Role | API |
|---|---|---|
| `Tigls/mb-getrandom@0.1.0` | **OS entropy source** | `pub fn getrandom(len : Int) -> Result[Bytes, String]` |
| `cc06b/mooncry@0.13.1` | **pure crypto ops** | `aes_gcm_encrypt/decrypt`, `sha256`, … |

`mb-getrandom` is a thin OS-entropy shim with a single public function and
per-backend system calls:

- **Linux**: `getrandom(2)`, with `/dev/urandom` fallback for kernels < 3.17.
- **macOS / *BSD**: `arc4random_buf`.
- **Windows**: `BCryptGenRandom`.
- **JS/WASM**: Web Crypto (`crypto.getRandomValues` / `crypto.randomBytes`).

(Verified from `.mooncakes/Tigls/mb-getrandom/src/lib/getrandom_stub.c` and
`getrandom_native.mbt`. Its internal `extern "C"` stub is the package's own
implementation detail — from our side it is an ordinary mooncake call, no FFI
for us to write or maintain.)

No DRBG layer is needed: the OS entropy syscalls above are designed for direct,
frequent use, and `requestState` sealing is low-frequency (one per
`input_required`). Each `seal` calls `@getrandom.getrandom(12)` for a fresh
random nonce — no counter to coordinate across instances, no DRBG state to
synchronize. Simpler = harder to get wrong.

**Usage** (all in `src/server/`, never in client packages):

```moonbit
// AES-256 key — once at server startup
let key = match @getrandom.getrandom(32) {
  Ok(k) => k
  Err(e) => abort("failed to read OS entropy for requestState key: {e}")
}

// GCM nonce — per seal
fn next_nonce() -> Bytes {
  match @getrandom.getrandom(12) {
    Ok(n) => n
    Err(e) => abort("failed to read OS entropy for nonce: {e}")
  }
}
```

Real random nonces — no counter coordination across instances, no ChaCha20
DRBG state to thread or synchronize. Windows is supported out of the box
(unlike the earlier `/dev/urandom`-only sketch).

**Why both mooncakes are kept** (not either-or): they are non-overlapping.
`mb-getrandom` does *only* OS entropy; `mooncry` does *only* crypto math and
ships no RNG (confirmed: zero `extern`/`getrandom`/`urandom` in its sources).
The AES-GCM path needs both: `mb-getrandom` for key + nonce, `mooncry` for the
cipher itself.

**Error handling**: `getrandom` returns `Result[Bytes, String]`. Failure means
the OS entropy pool is unavailable — extremely rare on healthy systems but not
impossible (early boot, heavy sandboxing). The server SHOULD surface this as a
fatal startup error for key generation (no safe fallback exists for an AEAD
key) and as a retryable error for per-request nonces.

### What the codec does NOT do

- It does not provide replay protection beyond the TTL window and principal
  binding. Cross-request replay within the window is bounded by
  `params_digest` (the blob only opens for the same method+params), but the
  *same* retry could theoretically be submitted twice within the window.
- It does not rotate keys. If you need key rotation, the blob format would need
  a key-id prefix — out of scope for 0.15.0; document as a limitation.

---

## Suggested sequencing

Dependency-aware, keeps the tree compiling:

1. **0** (housekeeping + version constant + mooncry dep) — unblocks all.
2. **11** (error codes) — small, independent, needed by 7.5/8.7.
3. **1** (server: delete initialize/ping/setLevel/subscribe) — clean cut.
4. **2** (per-request `_meta`) — must land with 1; without `_meta` no modern
   request is valid.
5. **3** (server/discover) — needed by the era probe (10).
6. **7** + **8** (HTTP transports, modern) — the bulk of protocol work.
7. **Crypto** (request_state.mbt + AesGcmStateCodec) — independent of protocol
   flow; can be built/tested in isolation.
8. **5** (server MRTR using the codec) — depends on Crypto.
9. **4** (subscriptions/listen) — large but self-contained.
10. **6** (client MRTR) — depends on 5 (needs a server to test against).
11. **10** (era probe + `legacy/` pkg) — can start in parallel once 3 lands;
    the legacy pkg is self-contained.
12. **12, 13** (caching, tests/docs) — polish.

---

## Open items for review

- **`_meta.logLevel` wiring (decided: not implemented)**: the spec replaced
  `logging/setLevel` with a per-request `_meta` field, but the Logging feature
  itself is Deprecated (SEP-2577: "new implementations should not add
  support"). The client can still send the field (`build_request_meta`'s
  `log_level~`, for interop with servers that honor it); this SDK's server
  neither reads it nor emits log-level-gated messages, deliberately.
- **Server-side cancellation action (follow-up)**: inbound
  `notifications/cancelled` is now routed away from the request path instead
  of being rejected, but actually stopping in-flight work (request lifecycle
  tracking) is not implemented.
- **Era probe + ClientBackend dispatch (10b — follow-up)**: the modern
  `MCPClient` is pure 2026-07-28 and `LegacyClient` exists in
  `src/client/legacy/`, but `connect_http`/`connect_stdio` do not yet probe
  (`server/discover`) and fall back. Modern-only deployments work today;
  wiring dual-era support is the next step.
- **HTTP per-request SSE streaming (follow-up)**: `subscriptions/listen`
  delivers its acknowledgment over HTTP; ongoing notification streaming on a
  single POST response needs per-request SSE (transport currently returns one
  JSON body per POST). stdio fully supports ongoing streams.
- **`requestState` clock (follow-up)**: `MCPServer` defaults `clock` to a stub
  returning 0; production servers must inject a real clock via `with_clock`
  for `requestState` expiry enforcement.
- **`ping` on legacy client**: the modern server drops `ping`. `LegacyClient`
  in `src/client/legacy/` does not yet expose a `ping` helper; add it there if
  needed for liveness checks against legacy servers.
- **Session-capable HTTP transport**: `LegacyClient` uses the transport's
  send/receive directly; a dedicated session-aware HTTP client
  (`legacy/http_session.mbt`) is not yet implemented. Legacy HTTP servers that
  require `Mcp-Session-Id` are not yet supported.
- **Nonce source (resolved)**: `Tigls/mb-getrandom` provides OS entropy
  directly (`getrandom(len) -> Result[Bytes, String]`) across native/JS/WASM
  with per-OS system calls (getrandom/arc4random_buf/BCryptGenRandom). Both
  `mb-getrandom` and `mooncry` are kept — entropy vs. crypto, non-overlapping.
  Both are server-only (see *Crypto boundary*). No client-side crypto.
