# MCP 2026-07-28 conformance

This branch is completing the remaining protocol and runtime requirements. **It is not yet a complete MCP 2026-07-28 implementation.** Use the evidence below to distinguish wire-model support from runtime guarantees.

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
| Server result metadata merge | Preserves handler metadata and extensions; adds server identity without mutating the supplied top-level result/metadata maps | `src/server/tool_wire_wbtest.mbt` |
| Shared result metadata model | Result type, nonnegative integral TTL, public/private scope, `_meta`, extensions, server-info accessor; integrated into tool calls, resource results, prompt results | Wire-model and client/server codec tests |
| Resources | Complete definitions/templates; multiple text/blob contents with per-content metadata; strict codecs, no MIME defaults | `src/protocol/types/resource_wire_test.mbt`; resource client/server codec tests |
| Prompts | Titles, icons, argument titles/optional required, definition/result metadata, message extensions; nonstandard annotations retained as extensions | `src/protocol/types/prompt_wire_test.mbt`; prompt client/server codec tests |
| RequestContext and authentication | Separate business arguments, trusted principal, input responses, restored continuation state, cancellation and progress; HTTP authentication returns `Principal?` | `src/server/request_context_wbtest.mbt`; HTTP I/O tests |
| MRTR runtime | Real clock, principal/method/operation binding, expiry/tamper checks; sealed input definitions validate exact response keys and unions before dispatch; stateless valid retries retain original business state | Request-state, request-context and `src/server/input_state_wbtest.mbt` tests |
| MRTR output and exchange limits | Malformed handler-authored input requests fail with -32603; client exchange limits stop without a final unconsumable interaction | `src/server/input_request_wbtest.mbt`; `src/client/mrtr_rounds_io_wbtest.mbt` |
| Request cancellation | Scoped server task ownership, no late response after cancellation, local client wait release, typed stdio ids, owned HTTP stream closure | `src/server/cancellation_runtime_wbtest.mbt`; `src/client/request_cancel_io_wbtest.mbt` |
| SSE disconnect | Single-writer keepalive flushes detect disconnect, close reply queues and cancel handlers; comment-only heartbeats are not EOF | `src/transport/sse_flush_io_test.mbt`; HTTP cancellation test |
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
| Stdio frame ownership | Concurrent large requests/notifications serialize as complete frames on native/JS; partial-write failures close the channel; best-effort cancellation has a bounded wait | `src/transport/stdio_frame_io_test.mbt`; client response-pump tests |

Round-trip checks compare JSON values, not whitespace or object-key order. Top-level map isolation does not imply a deep copy of every nested JSON object.

## Remaining acceptance work

- Arbitrary JSON Schema 2020-12 execution beyond the supported validator profile: remote references/resource identifiers, dynamic scope, vocabulary, unevaluated semantics and general ECMA-262 patterns remain unsupported. Registration fails explicitly rather than advertising unenforced constraints.
- Typed numeric-value precision and remaining open-extension wire edge cases (including convenience models using Double); lossless raw JSON paths do not imply lossless every typed field.
- Remaining normative sampling/elicitation policies and input-response lifecycle edges beyond the tested wire/constraint/correlation guarantees.
- Full conformance matrix, remaining transport E2E cases and final documentation review.

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
combinators, precise numeric constraints and same-document static `$ref`/`$defs`,
including recursive plans with depth budgets. Schema storage and execution use owned
snapshots; mutating the original definition does not change the registered contract.

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
`colmugx/json-schema@0.0.1` dependency was not found in the registry during verification.
Before publishing this SDK revision, publish the library revision containing local-ref
support, update the dependency version if necessary, and verify a standalone SDK build
without the workspace override. Workspace success is not proof of registry availability.

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

- Sampling message/result roles use `Role`; content uses `SamplingContent::Single` or `Multiple` rather than one general `ContentBlock`. Use `CreateMessageResult::text` for simple assistant text and `CreateMessageRequest::new` for requests. `max_tokens` preserves the schema's numeric value as `Double`.
- Advertise sampling tool support only when your handler supports it. `ToolChoiceMode::Disabled` encodes the wire value `none`; omitted preferences/choice/content metadata remain omitted.
- Empty server registries no longer advertise capabilities by default. Register entries or call `with_tools`, `with_resources`, or `with_prompts` explicitly for an intentionally empty API. `enabled=false` overrides registration without deleting it; disabled methods return `-32601`.
- `MCPServer` installs its live schema resolver for HTTP header validation. Custom dispatch owners must install `HttpTransport::set_tool_schema_resolver` before accepting calls. These header checks are distinct from JSON Schema execution validation.

## Target support

Follow `src/transport/moon.pkg`: HTTP server and stdio server I/O are native/wasm; JS has real HTTP and stdio clients. wasm-gc transport stubs are not production transport implementations.

## Validation record: wire models, runtime, completion, capabilities and progress

After these slices' changes:

- Native check with `--deny-warn`: passed; tests: **456/456**.
- JS check with `--deny-warn`: passed; tests: **398/398**.
- Wasm check with `--deny-warn`: passed (check-only; Wasm tests were not run).
- Native release build: passed.
- `moon fmt`, `moon info`, and `git diff --check`: passed.
- Independent validator package tests: **30/30** on native and **30/30** on JS.
- Official validator corpus, native release runner: **962/1301** standard cases (0 mismatches, 337 unsupported, 2 rejected); optional cases **535/1036**. Coverage remains incomplete, with the expected runner exit code 1. Counts are unchanged by the syntax-only number parser fix; this is not a full Draft 2020-12 conformance claim.

These results cover the current slice, not the remaining acceptance work. Checks/tests use `--output-json`; commands run directly with `moon`.
