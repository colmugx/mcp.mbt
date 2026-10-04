# Official conformance and native release benchmark

Use this guide from the **independent module root**, not its enclosing MCP
workspace. The library remains all-target; the two measurement/test executables
are explicitly native-only.

## One complete campaign

```sh
moonx benchmarks/run-campaign.mbtx
```

This checks the toolchain, fetches and preserves the pinned official corpus,
prepares a manifest, runs native check and necessary unit tests, builds both
executables with `--target native --release`, verifies failure handling, runs
all official cases, then measures 11 scenarios in **five serial fresh processes**
each. The scenario order rotates between repetitions. Raw command/stdout/stderr/
exit evidence is retained, including partial logs on failures and timeouts.

For a short smoke campaign (one repetition, 20 ms minimum measured time):

```sh
moonx benchmarks/run-campaign.mbtx smoke
```

Formal runs use five warmup batches and at least 200 ms per measured process.
A single unusually expensive batch may exceed that minimum. Smoke is an
infrastructure check, not the published performance baseline.

Artifacts live in ignored `benchmark-results/`. The campaign refuses to start
if `logs/` or `runs/` already exists; move or remove them after saving any evidence
you want to keep. The verified official checkout can be reused. A changed pin
requires moving/removing that checkout too, rather than silently reusing another
revision. Fetch/build/check/test errors are fatal.

## Scripts and ownership

| Script / package | Responsibility |
|---|---|
| `fetch-suite.mbtx` | Fetch exact upstream Git revision; preserve original files and MIT license |
| `prepare-suite.mbtx` | Enumerate complete draft2020-12 corpus and remotes, generate count manifest |
| `verify-harness.mbtx` | Check missing input, empty filters, corrupt counts, invalid benchmark, timeout and compile-failure handling; remove probes |
| `run-campaign.mbtx` | Orchestrate gates, native builds, child processes, logs and campaign state |
| `report.mbtx` | Validate report provenance/counters, summarize conformance and repeated measurements |
| `cmd/conformance` | Native official-suite runner linked to this unpublished local library |
| `cmd/benchmark` | Native compile/boolean/diagnostic and precise-scenario measurement runner |

`.mbtx` scripts always use **`moonx`**. Only orchestration scripts import
`moonbitlang/async@0.21.3`; it is not a library runtime dependency. Native package
runners use `moon run` or their built executables, avoiding registry imports of
an unpublished local validator.

## Official-suite TDD

```sh
moonx benchmarks/fetch-suite.mbtx
moonx benchmarks/prepare-suite.mbtx
moon run cmd/conformance --target native --release --output-json
moon run cmd/conformance --target native --release --output-json -- --file multipleOf.json
moon run cmd/conformance --target native --release --output-json -- --file multipleOf.json --group 0 --case 0
```

Indices are zero-based. Case IDs are `file.json#group/case`. A filtered run
writes `conformance-filtered.json` by default so it does not overwrite the full
campaign evidence. `--manifest PATH` and `--output PATH` override defaults.
Missing input, malformed fixtures/manifest, duplicate or unsafe paths, incorrect
counts and an empty selection are harness errors, not skipped tests.

| Native runner exit | Meaning | Campaign / CI policy |
|---|---|---|
| 0 | Every selected case matched its expected validity | Accept |
| 1 | Ordinary mismatches or known unsupported/rejected schemas | Accept **only** from `cmd/conformance`, show incomplete x/N |
| 2 | Harness/runtime failure, including boolean/diagnostics disagreement | Fail |
| Other / signal / timeout | Unexpected execution failure | Fail |

The pinned standard denominator is **1301**, with all **1036 optional** cases
reported separately and no proposal cases at this pin. Unsupported/rejected
schemas stay in the denominator. Annotation-only `format` is recorded explicitly;
optional format results are not a claim of format-assertion support. Full results
and per-file coverage are the TDD backlog. The runner is not a formal compliance
proof, even when a future run reaches 1301/1301.

Necessary unit tests cover number/parser precision, regex-profile contracts,
owned compiled plans, diagnostic paths/branch isolation, typed/resource errors
and runner accounting; official keyword examples are not duplicated as generated
unit-test blocks.

## Performance scenarios

| Scenario | Timed operation / reuse |
|---|---|
| `official_compile` | Compile one eligible official schema; optimizer sink retains result |
| `official_validate` | Boolean validation of one eligible official instance, compiled plan reused |
| `official_compile_validate` | Recompile once per group, validate all its instances; cost per instance |
| `official_diagnostics` | Build diagnostics for one eligible instance, compiled plan reused |
| `tool_arguments` | Closed tool object, exact decimal and pattern, valid/invalid/extra-field inputs |
| `structured_result` | Structured output object/array, valid and invalid inputs |
| `array1024` | Validate one 1024-item integer array |
| `unique128` | Distinct 128-item array and a duplicate-array rejection |
| `branches` | Object/string/array/numeric disjunctions |
| `exact_decimal` | Precise decimals, large integers and numeric counterexamples |
| `pattern` | Supported anchored lookahead chain, accepting and rejecting inputs |

Official performance workloads include **only cases proven correct** by the
full conformance report, then independently preflight boolean and diagnostic
results. At this baseline that is 921 instances across 230 schemas; 380 standard
cases are excluded from timing but **not** from conformance. Every measurement
records eligible IDs and exclusions. Never compare changing eligible sets as a
stable speed index. Synthetic workloads also preflight their expected outcomes.

```sh
moon run cmd/benchmark --target native --release --output-json -- --scenario official_validate --output benchmark-results/manual.json
moon run cmd/benchmark --target native --release --output-json -- --scenario exact_decimal --smoke --output benchmark-results/manual-smoke.json
moonx benchmarks/report.mbtx
```

Parsing, loading, process startup, preflight and report serialization are outside
the clocks. Compilation is inside compile/compile-validate clocks. Boolean checks
include numeric/depth preflight; diagnostics additionally allocate failure data.
Timed loops include loop and correctness-counter bookkeeping. Per-batch counts
are checked after timing so dead results or incorrect acceptance counts cannot
silently produce a favorable result.

JSON includes operations, accepted results, per-batch counters, iterations,
elapsed microseconds, ns/op, operations/sec, mode/unit, warmup, build/target,
revision and exact eligible IDs. Reports show **median/min/max across fresh
processes**; these are aggregate workload costs, not per-request latency
percentiles. Build/runtime/counter/provenance errors fail CI. Hosted-runner noise
is not an absolute throughput gate or evidence of being the fastest library.

## Independent GitHub Actions workflow

`.github/workflows/schema-benchmark.yml` runs on `main` pushes and manual dispatch
once this directory is a repository root. It pins compiler/core, defaults to
native release/full repetitions, writes the Actions step summary and uploads
corpus/license/manifest/results/raw logs even when the campaign fails. Ordinary
coverage gaps are visible without making the workflow red; unrelated failures
are never accepted via blanket `continue-on-error`.

See [provenance](../docs/fixture-provenance.md), [support contract](../docs/conformance.md)
and [local baseline](baseline.md) before publishing claims or comparing validators.
