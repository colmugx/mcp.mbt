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
- Separate syntax-only number parsing in the independent validator from its bounded exact-arithmetic evaluation, so valid large JSON-RPC integers remain readable without silently extending validation support.

## Why

Previously, retaining tool schemas did not enforce their execution contracts. Validation now protects handlers from invalid input and prevents publishing structured successes that contradict the advertised output schema. Compile-once plans keep repeated calls free of schema-compilation work. Preserving numeric literals avoids accepting rounded decimals or miscomparing HTTP mirror values.

Elicitation and retry inputs are execution contracts too: client-side checks alone cannot protect a server from malformed or substituted responses. Authenticated correlation keeps the runtime stateless while independently validating inputs. Bounded retries avoid asking users for information that cannot be consumed. URL decoding now follows the pinned 2026-07-28 wire shape instead of requiring a legacy compatibility field.

The independent validator adds bounded same-document `$ref`/`$defs` support for these scenarios. It remains a partial 2020-12 implementation: unsupported remote/dynamic/unevaluated semantics fail explicitly at registration. This change does not claim complete MCP conformance or implement OAuth client lifecycle.

Releasing this dependency update still requires a published validator revision and a standalone SDK build without the local workspace override; the declared validator version was unavailable during the earlier registry verification.
