# Local native release baseline

This is the first full-corpus/native-campaign baseline, not a cross-library
comparison or a claim to be the fastest validator.

## Environment and corpus

- Local Darwin arm64, kernel 27.0.0; exact CPU model not recorded.
- Moon `0.1.20260920` (`914d7da`); moonc `v0.10.14+7d59c7ec9`.
- Native release, command: `moonx benchmarks/run-campaign.mbtx`.
- Five serial fresh processes per scenario; five warmup batches and at least
  200 ms measured time per process. Scenario order rotates across repetitions.
- Official revision: `5b0ee1613e45fcc2bddac00e07c19cd49b00d8a8`.
- Full standard conformance: **921/1301**, 0 mismatches, 372 unsupported and
  8 rejected. Optional: 525/1036, recorded separately; no proposal cases.
- Official timing eligibility: **921 instances / 230 schemas**, including
  572 expected-valid and 349 expected-invalid instances. The other 380 standard
  cases remain in conformance but are excluded from timing.
- Local development tree, not a tagged independent release. The surrounding
  Git HEAD is not an independent library revision. CI artifacts after moving
  this module to its own repository will provide the actual library commit.

## Results

Values below are **median [min, max] across five process averages**, in ns/op,
rounded for readability. Raw JSON preserves counters and unrounded values.

| Scenario | Unit | Median ns/op | Min | Max |
|---|---|---:|---:|---:|
| Official compile | schema | 2090.75 | 2072.67 | 2141.73 |
| Official boolean validation | instance | 362.69 | 359.72 | 363.29 |
| Official compile + validation | instance | 895.99 | 884.74 | 899.90 |
| Official diagnostics | instance | 403.94 | 399.58 | 406.57 |
| Tool arguments | instance | 1366.58 | 1350.84 | 1375.39 |
| Structured result | instance | 1354.36 | 1329.78 | 1372.66 |
| 1024-item array | instance | 393805.69 | 391956.21 | 398014.25 |
| Unique array workload | instance | 887967.55 | 885032.81 | 895806.36 |
| Composition branches | instance | 585.81 | 576.92 | 591.10 |
| Exact decimals | instance | 1468.63 | 1459.35 | 1484.42 |
| Pattern profile | instance | 825.71 | 817.98 | 833.88 |

Startup, parsing/loading, preflight and JSON reporting are excluded. Timed loops
include operation/acceptance counting. Compile uses an optimizer sink; cached
validation includes numeric/depth preflight. Compile+validate recompiles once
per group, so it is **not** compilation per instance. Diagnostics includes
failure-array construction. Synthetic scenarios mix their declared valid and
invalid examples; `unique128` includes a distinct 128-item array and a short
duplicate rejection, not 128-item work on every operation.

## Interpretation

The official average reflects only the current correctness-verified subset;
it does not measure references, dynamic scopes or unevaluated semantics. As
coverage grows, that subset changes. Preserve eligible case IDs and compare a
fixed common subset before interpreting a throughput change as an optimization.

Large arrays and uniqueness already cost substantially more than small tool
objects. This evidence supports targeted optimization work rather than a single
misleading "JSON Schema speed" number. No hard speed gate is imposed on noisy
hosted runners. Do not infer individual request latency percentiles from these
aggregate process measurements.

The campaign retained original corpus/license, manifest, per-case conformance,
55 measurement JSON files and command/stdout/stderr/status evidence under
`benchmark-results/`. These generated artifacts are ignored locally and uploaded
by the independent workflow. See [the reproduction guide](README.md).
