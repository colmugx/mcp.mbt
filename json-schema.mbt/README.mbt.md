# colmugx/json-schema

A compile-once JSON Schema validator for MoonBit, built around **precise
2020-12 validation scenarios** rather than permissive approximations.

**Status: development milestone, not a complete 2020-12 implementation.**
References, dynamic scope and unevaluated annotations are not implemented yet.
Schemas requesting those semantics fail compilation explicitly. See
[the support contract](docs/conformance.md) before adopting the library.

## Use it for

- Closed tool/request argument objects (`additionalProperties: false`).
- Structured result validation, tuples, array membership and dependencies.
- Exact decimal `multipleOf`, integer checks and numeric bounds.
- Unicode code-point string lengths and an explicitly supported pattern profile.
- Reusing one owned compiled schema for many instances.

The module has no dependency on the surrounding MCP project. Its local
`moon.work` isolates it from an enclosing MoonBit workspace, so the directory
can be moved into its own repository.

## Quick start

Import `"colmugx/json-schema"` in your package. Parse numbers through this
library when their original decimal values matter:

```moonbit nocheck
///|
let document = @json-schema.parse(
  "{\"type\":\"object\",\"required\":[\"amount\"],\"properties\":{\"amount\":{\"type\":\"number\",\"multipleOf\":0.1}},\"additionalProperties\":false}",
)

///|
let schema = @json-schema.Schema::compile(document)

///|
let instance = @json-schema.parse("{\"amount\":0.3}")

///|
let valid = schema.valid(instance)

///|
let failures = schema.faults(instance)
```

These operations can raise errors; propagate or catch them at your application's
boundary. A malformed/unsupported schema is not a valid compiled schema. A
malformed numeric node or exhausted traversal budget is not an ordinary `false`
validation result.

### Choose the result you need

- `schema.valid(instance)` short-circuits assertion failures and does not build
  a diagnostic array.
- `schema.faults(instance)` returns failures with `instance_path`, `schema_path`,
  `keyword` and `message`. Paths use JSON Pointer escaping.
- Both methods check the instance's numeric representations and traversal budget.
  Failed speculative `anyOf`, `oneOf`, `not` and `if` branches do not leak errors
  into a successful result.

### Preserve number precision

A floating-point value cannot recover digits lost before validation. This
library's parser keeps number lexemes in `Json::Number`'s `repr` field; numeric
predicates use integer coefficients and decimal scales, not an epsilon or a
rounded decimal quotient. Core-parsed or programmatically constructed numbers
without a lexeme use the available finite `Double` representation instead.

Do not construct inconsistent `Json::number(value, repr=...)` nodes: numeric
representations are checked, not silently discarded.

## Supported now

The compiler/evaluator covers boolean schemas, `type`, `const`, `enum`, numeric
bounds and `multipleOf`, string lengths and patterns, object properties/names/
dependencies, 2020-12 `prefixItems`/`items`, array counts/`contains`/`uniqueItems`,
and `allOf`/`anyOf`/`oneOf`/`not`/`if`/`then`/`else`.

`format` and content keywords are annotations, **not format/content assertions**.
Unknown extension keywords are annotations. Known malformed supported keywords
are compile errors. An unimplemented known semantic keyword is an explicit
unsupported error, not an ignored assertion.

## Evidence and development

The full pinned official draft2020-12 corpus currently reports **921/1301**
standard cases matched: **0 mismatches, 372 unsupported, 8 rejected**. Optional
cases are reported separately (**525/1036**); format assertions are not enabled.
This is visible progress toward conformance, **not a complete-draft claim**.
Unsupported and rejected cases stay in the denominator.

Run these commands from this independent module's root:

```sh
moon check --target native --deny-warn --output-json
moon test --target native --deny-warn --output-json
moon check --target js --deny-warn --output-json
moon test --target js --deny-warn --output-json
moon check --target wasm --deny-warn --output-json
moonx benchmarks/run-campaign.mbtx
```

The campaign downloads the official corpus, checks and builds native release
executables, runs every official case and measures 11 scenarios in five fresh
processes each. It saves the corpus, provenance, detailed outcomes and logs in
`benchmark-results/`. Move or remove the previous campaign's `logs/` and `runs/`
before starting another; existing evidence is not overwritten silently.

For a shorter infrastructure check, use
`moonx benchmarks/run-campaign.mbtx smoke`. For case-level TDD, see
[the runner guide](benchmarks/README.md). Ordinary official-suite gaps do not
fail CI; compilation, runtime/harness failures and invalid performance results
**do**. Unit tests cover library-specific contracts rather than duplicating the
full official corpus.

The independent [benchmark workflow](.github/workflows/schema-benchmark.yml)
runs on pushes to `main` and manual dispatch once this directory becomes the
repository root. Standalone `.mbtx` orchestration uses **`moonx`**; the native
package runners can be invoked with `moon run`.

## Performance policy

Correctness comes first. Compilation hoists schema parsing and regular-expression
compilation out of repeated validation; object checks share a property walk.
The current implementation still performs a numeric/depth preflight and uses a
quadratic exact-equality check for `uniqueItems`. It does **not** yet claim to be
the fastest validator. Performance claims require reproducible benchmarks,
representative valid/invalid cases and the same semantics on both sides.

## License

Apache-2.0. Vendored conformance data, when present, retains its upstream license
and pinned-source attribution.
