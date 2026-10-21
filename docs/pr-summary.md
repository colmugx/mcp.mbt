# MCP execution contracts and MRTR correctness

## What changed

- Integrate the independent `colmugx/json-schema` validator into tool registration and execution.
- Compile and own input/output schema plans before atomically publishing a tool definition.
- Reject unknown tools and invalid arguments with `-32602` before invoking handlers; reject missing or invalid successful structured output with `-32603`.
- Preserve tool errors, result metadata, cancellation and MRTR context separation.
- Preserve numeric lexemes across argument builders, requests, retries, legacy metadata rewriting, structured results and mirrored HTTP headers; expose `parse_json` through the SDK facade.
- Validate restricted elicitation schemas before user interaction and accepted form content against immutable compiled constraints, in both MRTR and legacy callbacks.
- Seal requested input definitions with continuation state; reject missing/extra response keys, mismatched response types and invalid form/roots content before business dispatch.
- Reject malformed handler-authored input requests as server errors, accept standard URL elicitation without `elicitationId`, and stop exhausted MRTR loops before an unusable user interaction.
- Add focused regression tests and update customer-facing documentation with supported schemas, error behavior and migration guidance.
- Update CI checkout and target gates for the independent validator workspace.
- Add exact JSON integer request IDs and peer error codes, preserving original wire literals while using canonical numeric identity for response routing, cancellation and subscriptions.
- Reject malformed or fractional IDs before sending requests, prevent duplicate active numeric identities, and preserve numeric-versus-string subscription IDs.
- Preserve exact numeric progress-token literals and identity through request metadata and callbacks, avoiding collisions between adjacent large values or rounded decimals.
- Reject fractional or out-of-range MRTR timestamps and widen expiry-skew arithmetic to prevent overflow.
- Separate syntax-only number parsing in the independent validator from its bounded exact-arithmetic evaluation, so valid large JSON-RPC integers remain readable without silently extending validation support.

## Why

Previously, retaining tool schemas did not enforce their execution contracts. Validation now protects handlers from invalid input and prevents publishing structured successes that contradict the advertised output schema. Compile-once plans keep repeated calls free of schema-compilation work. Preserving numeric literals avoids accepting rounded decimals or miscomparing HTTP mirror values.

Elicitation and retry inputs are execution contracts too: client-side checks alone cannot protect a server from malformed or substituted responses. Authenticated correlation keeps the runtime stateless while independently validating inputs. Bounded retries avoid asking users for information that cannot be consumed. URL decoding now follows the pinned 2026-07-28 wire shape instead of requiring a legacy compatibility field.

The independent validator now supports explicit external resources, `$id`/anchors, dynamic references, unevaluated constraints and standard-vocabulary custom dialects. Per-tool registries compile into owned input/output plans; registration never performs network resolution. General regex/optional format-assertion profiles remain bounded, and this is not an unconditional complete-conformance or OAuth client-lifecycle claim.

The earlier `colmugx/json-schema@0.1.3` dependency was verified by a standalone SDK check, 409/409 tests and native release build without the local validator override. The current workspace declares 0.1.4; that isolated registry record is historical, not a new verification of 0.1.4. The separately approved checked-error API migration now removes all 48 Warning 78 diagnostics: default check, native/JS/Wasm deny-warn checks and native release build pass without suppression or CI changes. Current workspace tests pass 488/488 native and 440/440 JS; channel E2E tests pass 29/29 native and 5/5 JS.

The final integration slice also validates sampling tool-use/result histories, URL syntax and subscription filters, corrects HTTP protocol-error statuses, preserves peer errors from HTTP error bodies, and rejects modern duplex/miscorrelated responses while ending owned SSE reads at the final response. Real client/server HTTP regressions cover schema contracts and missing-capability errors.
