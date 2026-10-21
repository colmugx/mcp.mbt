# MCP 2026-07-28 conformance

This checkout implements the protocol/runtime slices below, including external schema resources and the final integration regressions. **This is not an unconditional complete MCP 2026-07-28 conformance claim.** Optional validator profiles, host obligations and the checked-error API migration are explicit below. Wire-model support, runtime guarantees and release readiness are separate acceptance dimensions.

## Protocol baseline

The SDK's protocol constant is `2026-07-28`. Reproducible upstream schema fixtures are stored in `tests/fixtures/mcp/2026-07-28`, pinned to specification revision `271ecc9accafdd9b83a3c869fa67c22953b2af80`. Their SHA-256 values were checked against the fixture README before implementation.

OAuth authorization client lifecycle, PKCE, dynamic client registration, and token refresh management are excluded. Bearer-token support, server-side authentication hooks, and protected-resource metadata remain in scope.

## Verified implementation slices

| Area | Current support | Evidence |
| --- | --- | --- |
| ContentBlock | Text, image, audio, resource links, embedded text/blob resources, unknown content; annotations, icons, `_meta`, extensions | `src/protocol/types/content_block_test.mbt`; client content-codec tests |
| Tool definition | Complete wire fields; full input/output schemas retained without projection; strict known-field decoding | `src/protocol/types/tool_wire_test.mbt` |
| Tool result | Content, arbitrary JSON `structuredContent`, optional `isError`, `_meta`, result extensions | `src/protocol/types/tool_wire_test.mbt`; `src/client/content_codec_wbtest.mbt` |
| Full tool registration | Owns a deep snapshot of the definition; compiles schemas before atomic registry replacement | `src/server/tool_wire_wbtest.mbt`; `src/server/schema_validation_wbtest.mbt` |
| Tool execution validation | Compile-once input checks before handler/MRTR dispatch; successful structured output checked against declared outputSchema; input errors -32602, output-contract failures -32603 | `src/server/schema_validation_wbtest.mbt` |
| Precise numeric wire values | Argument builders, request parsing, retries/legacy metadata, structured results and mirrored-header comparisons preserve numeric lexemes | `src/client/precision_wbtest.mbt`; schema-validation and header tests |
| Exact progress identity | Numeric tokens retain arbitrary decimal/exponent literals and compare by exact numeric identity; string tokens remain separate. Decoding returns `ExactNumber(JsonNumber)`; counters use exact `JsonNumber` values | `src/protocol/types/progress_exact_test.mbt`; `src/client/progress_wbtest.mbt` |
| Server result metadata merge | Preserves handler metadata and extensions; adds server identity without mutating the supplied top-level result/metadata maps | `src/server/tool_wire_wbtest.mbt` |
| Shared result metadata model | Result type, nonnegative integral TTL, public/private scope, `_meta`, extensions, server-info accessor; integrated into tool calls, resource results, prompt results | Wire-model and client/server codec tests |
| Resources | Complete definitions/templates; multiple text/blob contents with per-content metadata; strict codecs, no MIME defaults | `src/protocol/types/resource_wire_test.mbt`; resource client/server codec tests |
| Prompts | Titles, icons, argument titles/optional required, definition/result metadata, message extensions; nonstandard annotations retained as extensions | `src/protocol/types/prompt_wire_test.mbt`; prompt client/server codec tests |
| RequestContext and authentication | Separate business arguments, trusted principal, input responses, restored continuation state, cancellation and progress; HTTP authentication returns `Principal?` | `src/server/request_context_wbtest.mbt`; HTTP I/O tests |
| MRTR runtime | Real clock, principal/method/operation binding, expiry/tamper checks; sealed input definitions validate exact response keys and unions before dispatch; stateless valid retries retain original business state | Request-state, request-context and `src/server/input_state_wbtest.mbt` tests |
| MRTR output and exchange limits | Malformed handler-authored input requests fail with -32603; client exchange limits stop without a final unconsumable interaction | `src/server/input_request_wbtest.mbt`; `src/client/http_mrtr_rounds_e2e_wbtest.mbt` |
| Request cancellation | Scoped server task ownership, no late response after cancellation, local client wait release, typed stdio ids, owned HTTP stream closure | `src/server/cancellation_runtime_wbtest.mbt`; `src/client/stdio_request_cancel_e2e_wbtest.mbt` |
| SSE disconnect | Single-writer keepalive flushes detect disconnect, close reply queues and cancel handlers; comment-only heartbeats are not EOF | `src/transport/sse_flush_e2e_test.mbt`; HTTP cancellation test |
| Completion | Typed prompt/resource references, context arguments, shared strict result codecs, opt-in server registry and discovery flag | Completion protocol/client/server tests |
| Capabilities | Experimental, extensions and unknown fields; sampling context/tools, elicitation form/url, server completions/logging; nested MRTR enforcement | Capability protocol/client/server tests |
| Progress tokens | String and finite numeric identifiers, including fractional values; request metadata and notification codecs preserve their types | Progress protocol/client tests |
| Tool-list/discovery metadata | Tool-list cache hints and open metadata; full `discover_result` view retains versions/instructions; host source metadata and cursors retained separately | Result-metadata, discovery and host aggregation tests |
| JSON-RPC integer ids | Exact literal echo beyond Int32/binary64; typed canonical routing, equivalent numeric spellings, string/number isolation, duplicate checks, cancellation and subscription tags; fractions rejected | Protocol/client/server request-id tests; real reversed HTTP replies and stdio cancellation |
| Peer error handling | Exact integer code, message, data presence and unknown fields preserved in `RemoteError`; fractional and inconsistent numeric representations rejected, no narrowing or reserved-code aliasing | Error protocol/client tests; transport request-id tests |
| Client shutdown | Closing the client cancels owned requests; event-loop shutdown cleans pending waits; HTTP close wakes queue receivers | Request cancellation and HTTP client lifecycle tests |
| Elicitation models and validation | Restricted form schema shape; owned constraint compilation before interaction; accepted content validation, action/mode rules, optional URL compatibility identifier; both MRTR and legacy callbacks checked | `src/validation/elicitation_test.mbt`; elicitation protocol/client tests |
| Client capability configuration | Handler-driven defaults, explicit nested capability registration/configuration, rejection of advertised input support without handlers, disabled input dispatch | Capability configuration tests |
| Sampling models | Model preferences, tools/tool choice, typed context/roles, single-or-array multimodal and tool interaction content, metadata and unknown fields; strict client input/output codec checks | `src/protocol/types/sampling_test.mbt`; `src/client/sampling_wbtest.mbt` |
| Server capability consistency | Registry-derived tools/resources/prompts, explicit empty enablement or disabling, disabled methods return -32601; subscription agreement reflects enabled features | `src/server/feature_capabilities_wbtest.mbt` |
| HTTP mirrored headers | Standard header validation plus live registry-aware exact-path Mcp-Param checks, safe integers, case-insensitive names, UTF-8 sentinel decoding, missing/mismatched rejection before dispatch | `src/transport/header_validation_test.mbt`; HTTP 400/-32020 real round-trip test |
| MRTR result structure | At least one inputRequests/requestState required; malformed entries and field types rejected rather than dropped; state-only load shedding and omitted roots params accepted | `src/client/mrtr_result_wbtest.mbt` |
| Complete result publication | Known tool/resource/prompt handler wire shapes validated; invalid metadata TTL is rejected before serialization; explicit cache hints preserved and defaults fill omissions | `src/server/result_metadata_wbtest.mbt` |
| One-shot response routing | Single-reader temporary pumps dispatch progress and id-correlated responses without run(); concurrent/out-of-order HTTP replies cannot cross callers | `src/client/response_pump_wbtest.mbt`; real HTTP client regression tests |
| SSE byte decoding | Split multi-byte UTF-8 sequences and leading BOM retained across refills; malformed/truncated bytes fail rather than signal EOF | `src/transport/sse_wbtest.mbt` |
| Stdio frame ownership | Concurrent large requests/notifications serialize as complete frames on native/JS; partial-write failures close the channel; best-effort cancellation has a bounded wait | `src/transport/stdio_frame_e2e_test.mbt`; client response-pump tests |
| External schema execution | Per-tool registry, separate input/output retrieval bases, compiled ownership, atomic failed replacement; remote anchors/dynamic/unevaluated/custom-dialect execution | `src/server/schema_resources_wbtest.mbt`; real SDK HTTP contract test in `src/client/http_mrtr_rounds_e2e_wbtest.mbt` |
| Sampling history | Adjacent complete tool-use/result exchanges, role constraints, no mixed tool-result messages, duplicate/missing/extra correlation rejection; shared MRTR/legacy/server validation | `src/validation/sampling_history_test.mbt`; client/server input-request tests |
| URL syntax | Absolute URL syntax, authority/port/brackets/escape checks before interaction; no implicit fetching or HTTPS-only policy | `src/protocol/types/elicitation_url_test.mbt` |
| HTTP error and stream ownership | Protocol HTTP 400/404 mapping, exact peer errors from error status responses, id correlation, no modern independent server request, final SSE ends local read ownership | `src/transport/http_status_wbtest.mbt`; `src/transport/http_protocol_wbtest.mbt`; `src/client/http_mrtr_rounds_e2e_wbtest.mbt` |
| Subscription validation | Required filter object, strict known filter types, duplicate active-id rejection, acknowledgement before subsequent change notification | `src/server/subscription_validation_wbtest.mbt` |

Round-trip checks compare JSON values, not whitespace or object-key order. Top-level map isolation does not imply a deep copy of every nested JSON object.

## Acceptance boundaries and host obligations

The [155-definition routing index](protocol-definition-index.md) maps every fixed schema definition to its SDK representation, implementation family and test family. It is not 155 independent conformance tests or a formal proof of every MUST.

- The validator supports preloaded remote refs, resource identities/anchors, dynamic scope, unevaluated semantics and standard-vocabulary custom dialects. General ECMA-262 regexes, format assertions and custom keyword plugins remain outside the supported profile. The independent library's 1301/1301 standard result is **not** an MCP protocol test count; optional cases remain 547/1036.
- The explicitly approved error-API migration replaces failure-returning `Result[T, MCPError]` APIs with checked errors, resolving all 48 Warning 78 (`result_error_return`) diagnostics. Native/JS/Wasm deny-warn checks now pass without suppression or CI changes. Business handler callbacks retain explicit Result outcomes; see the client guide's error-handling section for the breaking call-site migration.
- Sampling handlers must enforce provider `maxTokens`, protect model access and implement application approval policy. The SDK passes exact values and validates tool-choice/history semantics; it cannot infer actual provider token consumption from returned content.
- Elicitation hosts must display the server and full URL, obtain consent before navigation, provide decline/cancel and form review, and enforce sensitive-data policy. The SDK does not pre-fetch/open URLs, identify secrets from field labels, or verify a third-party browser session. URL `Accept` is consent, not completion.
- Deprecated logging is preserved through raw notification callbacks and metadata but is not advertised by the server. No automatic cache, OAuth client lifecycle or single-use replay store is included.
- Known typed fields are checked and unknown extensions retained; retaining an extension does not implement its semantics. Programmatic Double values cannot recover digits already rounded before entering the SDK.
- Low-level HTTP server startup/receive APIs still translate task shutdown into their typed transport errors; custom service owners must distinguish expected task cancellation during teardown. Request-local cancellation and no-late-response guarantees are tested separately.

Cancellation is cooperative: asynchronous suspension points allow the runtime to stop work, while CPU-only handlers should check their context token. HTTP disconnect detection is bounded by keepalive writes, not instantaneous.

MRTR will retain stateless retry semantics: expired, tampered, cross-principal, cross-method, and cross-parameter state is rejected; a valid state may be retried for the same operation within its lifetime. A single-use replay store is not part of the default runtime.

## Migration: exact JSON-RPC integers

`RequestId` adds `Number(JsonInteger)`; numeric decoding uses this variant so the
original decimal/exponent spelling survives. Keep `Int` for convenient small ids,
but update exhaustive pattern matches. The pinned JSON schema defines numeric ids
as integers: fractions are invalid requests. Numeric equality is mathematical,
so `42` and `4.2e1` identify the same request; `"42"` is a separate string id.
Response routing, duplicate detection, subscriptions and cancellation use the
same canonical keys. Subscription metadata now retains the original id type;
it no longer stringifies numeric ids or includes JSON quotes inside string ids.

`RemoteError.code` and `MCPError::to_error_code()` now use `JsonInteger`. Use
`as_int() -> Int?` for checked switches over standard codes; handle `None` for
large application codes. Use `to_jsonrpc_error()` to serialize the complete peer
error without losing its exact code, data presence or extensions. Invalid raw
request ids fail before transport I/O instead of sharing an invented id zero.

The validator's preserving parser no longer applies its arithmetic scale budget
while reading wire JSON. Valid literals with very large exponents remain
serializable; schema compilation/evaluation still reject scales outside their
supported arithmetic range with explicit typed errors. This parser change is
in the independent submodule and must be included in the published dependency.

## Migration: tool wire models

- `ToolDefinition.description` is now `String?`; use `unwrap_or("")` only when displaying an absent description as empty is appropriate.
- Prefer `ToolDefinition::new` over manually filling all optional fields. Input schemas have an object root with `type: "object"`.
- `ToolResult` is owned by `protocol/types` and re-exported through `protocol/tool` and the root facade. Existing `text`, `success`, and `error` builders remain available.
- `ToolResult::structured(value, content~)` accepts any JSON value. `Some(Json::null())` represents an explicitly present null output; `None` means no structured output.
- `ToolResult.is_error` and `CallToolResult.is_error` are now `Bool?` so codecs retain omitted versus explicit false. Use `unwrap_or(false)` for the effective flag.
- `CallToolResult` now exposes `structured_content` and `metadata`. Server identity is accessible as raw JSON through `metadata.server_info()`; unknown identity fields are not discarded.
- Malformed known tool definitions/results now fail decoding rather than being silently dropped from lists. HTTP `x-mcp-header` violations are the protocol-mandated exception: those tools are excluded with a warning, leaving valid definitions available.

## Tool validation contract and dependency readiness

Tool registration compiles input and optional output schemas once using the independent
`colmugx/json-schema` library. Registration rejects malformed/unsupported schemas before
changing the registry. Runtime checks support closed objects, arrays, dependencies,
combinators, precise numeric constraints, local/preloaded external `$ref`/`$defs`,
resource `$id`/anchors, dynamic references, unevaluated constraints and supported
standard-vocabulary custom dialects. `tool_definition(..., schema_resources?,
input_base_uri?, output_base_uri?)` supplies an explicit per-registration resource
registry and separate retrieval bases. Both validators compile before the registry
entry changes. Owned plans retain neither a live resolver nor mutable source JSON;
mutating the original definition or resource table does not change the contract.
Compilation and evaluation never fetch network resources.

Invalid tool arguments never enter the handler. A successful result declaring an
output schema must contain matching `structuredContent`; absence differs from explicit
JSON null. Output-contract failures are internal errors, not successful tool results.
`isError: true` results and MRTR `input_required` results do not undergo successful-output
validation. Each MRTR retry validates its original business arguments; responses/state
remain in the request context, never injected into a closed argument object.

Use `@mcp.parse_json` when loading schemas or constructing structured JSON with precise
numbers. The wire paths preserve lexemes, but cannot recover digits already rounded by
another parser or a programmatically constructed Double. `format` is annotation-only;
patterns follow the independent library's documented supported profile. Default schema
and instance traversal budgets are 128; cyclic references fail with typed errors rather
than looping. See the independent [`json-schema.mbt` repository](https://github.com/colmugx/json-schema.mbt) and the checked-out `external/json-schema` submodule for its supported execution profile.

Development uses `moon.work` to resolve the local independent library. The declared
`colmugx/json-schema@0.1.3` was verified as published with `moon view`. An isolated
copy containing only the SDK module (no external-validator workspace member) resolved
that registry release and passed native check, 409/409 SDK tests and native release
build. The temporary copy and build artifacts were removed afterwards. This verifies
historical dependency readiness, not publication of these MCP changes. The current workspace declares validator 0.1.4; the registry-only record below applies to the earlier 0.1.3 revision, not a fresh isolated verification of 0.1.4.

## Migration: resources and prompts

- `ResourceReadResult` now contains `contents: Array[ResourceContents]` and result `metadata`. Replace single `uri` / `ResourceContent` records with `ResourceReadResult::text`, `blob`, or `new`.
- Client `ReadResourceResult.contents` now directly contains `ResourceContents`; match each entry's `data` as `ResourceData::Text` or `Blob`. Optional MIME types and both inner/outer metadata remain separate.
- Resource and template definitions now include title/icons/annotations/metadata. Use their `new` builders or the server's full-definition registration APIs rather than filling every optional field by hand.
- Prompt definitions/arguments add titles and extensions; definitions add icons and `_meta`. `PromptMessage` retains extensions and `GetPromptResult` retains result metadata. Use `PromptArgument::new`, `PromptMessage::new`, and `GetPromptResult::new` for empty optional fields.
- Resource and prompt definitions/results are owned by `protocol/types` and re-exported through their specialized protocol packages and the root facade.
- Known malformed resource/prompt entries now fail the operation instead of silently being filtered; optional `nextCursor` must be a string when present.

## Elicitation and MRTR validation contract

Form requests require `type: "object"` and a `properties` map with flat primitive
or string-enum multi-select schemas. The SDK validates known schema fields and
compiles execution constraints before calling an interaction handler. Unsupported
semantics fail closed. Accepted form content must match the compiled schema;
declined/cancelled forms and all URL-mode results must omit content. `format` and
`default` are annotations, not automatic format validation or submitted values.

The server seals input definitions inside authenticated continuation state and
validates exact response keys and associated result types on retry. This includes
form constraints and `file://` roots. The handler still receives its original
business continuation state, not the SDK envelope. State-only load shedding
requires no input responses; valid same-operation retries remain repeatable.

The client allows eight exchanges by default, and stops before an interaction
when there is no remaining retry budget. Necessary regression tests cover both
this limit over real HTTP and server-side rejection before business dispatch.

Migration: URL requests do not require `elicitationId`. Use
`ElicitationRequest::url(message, url)`; an optional compatibility identifier is
labeled `elicitation_id`. Its enum field is now `String?`. Old MRTR blobs lacking
the input-correlation envelope are rejected under this runtime; coordinate
instances sharing keys and versions during deployment.

## Migration: sampling and enabled capabilities

- Sampling message/result roles use `Role`; content uses `SamplingContent::Single` or `Multiple` rather than one general `ContentBlock`. Use `CreateMessageResult::text` for simple assistant text and `CreateMessageRequest::new` for requests. `max_tokens` preserves the schema integer as `JsonInteger`; `temperature` and model priorities use `JsonNumber`. The convenience request constructor accepts an `Int` token count and a `Double` temperature and now raises on non-finite temperature.
- Advertise sampling tool support only when your handler supports it. `ToolChoiceMode::Disabled` encodes the wire value `none`; omitted preferences/choice/content metadata remain omitted.
- Empty server registries no longer advertise capabilities by default. Register entries or call `with_tools`, `with_resources`, or `with_prompts` explicitly for an intentionally empty API. `enabled=false` overrides registration without deleting it; disabled methods return `-32601`.
- `MCPServer` installs its live schema resolver for HTTP header validation. Custom dispatch owners must install `HttpTransport::set_tool_schema_resolver` before accepting calls. These header checks are distinct from JSON Schema execution validation.

## Target support

Follow `src/transport/moon.pkg`: HTTP server and stdio server I/O are native/wasm; JS has real HTTP and stdio clients. wasm-gc transport stubs are not production transport implementations.

## Latest integration validation record

- Workspace native tests: **488/488**; JS tests: **440/440**. These totals include the local independent validator; they are not MCP-only protocol-case counts.
- Real-I/O channel selection (`moon test --target native --output-json -f 'e2e/*'`): **29/29** across HTTP, stdio, SSE and legacy; JS real-I/O selection: **5/5**.
- Default `moon check --output-json`, native/JS/Wasm `--deny-warn` checks and native release build: **passed with zero warnings and zero errors**. The 48 Warning 78 diagnostics were removed by the checked-error API migration, not suppressed.
- New registry error-boundary tests verify unchanged handler-error wire identity and cancellation precedence over returned handler errors. Existing real stdio/HTTP cancellation and cleanup assertions remain enabled; error-observing test tasks use `allow_failure=true` so the caller, not the whole group, handles their raised failures.
- Historical registry-only isolated SDK check, **409/409** tests and native release build: passed against published `colmugx/json-schema@0.1.3` (without the local validator override), before the checked-error migration and subject to its then-existing warnings. This historical result was not rerun for the current 0.1.4 dependency during the warning cleanup.
- Fixture SHA-256 checks match the fixed-source README. `moon fmt`, `moon info` and `git diff --check` were run. The 155-definition index records representation/evidence routing, not an automatic complete-conformance proof.
- One attempted `moon test src ... -f 'e2e/*'` selected zero tests; it is not acceptance evidence. The corrected workspace-wide commands above selected and passed the actual channel tests.

## Historical validation record: wire models, runtime, completion, capabilities and progress

Sampling responses are correlated with the request's tool-selection policy: `required` requires a `tool_use` block; `none` forbids one. The shared check runs for client MRTR responses, legacy sampling callbacks and server validation of bound input responses. Single-block and array content follow the same policy. `includeContext` recommendations remain SHOULD behavior, not a new hard rejection.

After these slices' changes:

- Native check with `--deny-warn`: passed; tests: **434/434**.
- JS check with `--deny-warn`: passed; tests: **392/392**.
- MRTR timestamps reject fractional/out-of-range values; expiry skew comparison uses widened arithmetic to avoid Int32 overflow.
- Wasm check with `--deny-warn`: passed (check-only; Wasm tests were not run).
- Native release build: passed.
- `moon fmt`, `moon info`, and `git diff --check`: passed.
- Independent validator package tests after restoring `moonbitlang/regexp@0.3.6`: **33/33** on native and **33/33** on JS. Vendored Unicode tables were removed; necessary private ECMA/General_Category/backreference adapters retain upstream-review markers. Unsupported patterns remain typed errors.
- Historical official validator corpus record from the core migration, native release runner: **962/1301** standard cases (0 mismatches, 337 unsupported, 2 rejected); optional cases **535/1036**. Coverage remains incomplete, with the expected runner exit code 1. The full corpus and dual-runtime benchmark were not rerun for the regexp 0.3.6 restoration; this is not a fresh coverage or full Draft 2020-12 conformance claim.

These results cover the current slice, not the remaining acceptance work. Checks/tests use `--output-json`; commands run directly with `moon`.
