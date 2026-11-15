# Non-blocking MCP quality CI

The SDK quality workflow is intentionally separate from the existing code-check workflow. It runs on pull requests, pushes to main, and manual dispatches. The jobs use GitHub Actions job-level continue-on-error, so conformance or benchmark failures never block the existing checks or merges.

The new executable fixtures live under `tests/sdk-quality/fixtures`, **outside the SDK's `src/` module source tree**. Only the new quality jobs copy those files into `src/conformance` inside their disposable runner checkouts before compiling them. The regular `check.yml` job never sees or builds these fixtures, so a fixture failure cannot turn the existing code check red.

## Protocol correctness

The workflow uses the official modelcontextprotocol/conformance runner against small MoonBit fixtures.

Server smoke scenarios:

- tools-list (2026-07-28)
- tools-call-simple-text (2026-07-28)
- server-stateless (experimental, reports fixture gaps separately; not included in smoke pass/fail)

Client smoke scenarios:

- tools_call
- request-metadata

This is an initial, deliberately small protocol smoke suite, not a claim of complete MCP conformance. The stateless test is a broader diagnostic run; its four known fixture-not-testable checks are reported as failures but do not fail the smaller smoke suite. This is not an expected-failure waiver for the fully implemented server. The existing MoonBit unit and integration tests remain in the regular check workflow. As the adapters grow, add scenarios here and move known failures into an explicit expected-failures baseline rather than silently skipping them.

## Throughput

The throughput job records two complementary measurements against the same MoonBit HTTP server:

1. A native MoonBit MCPClient drives the MoonBit MCPServer at concurrency 1, 4, 16, and 64, with 50 tool calls per worker. Each JSONL record includes request count, elapsed time, achieved requests per second, and errors.
2. MCP Inspector's mcpdo load mode measures server-facing end-to-end throughput at concurrency 1, 4, 16, and 64, with a ramp whose first stage is warm-up and a fixed duration per stage.

The Inspector is only the load generator; results are not used to rank programming languages. The MoonBit-to-MoonBit measurement gives a direct SDK round-trip signal, while the Inspector run provides a second, independently implemented load driver.

Both regular quality jobs upload raw logs and environment details as workflow artifacts. The workflow currently records results rather than enforcing a performance threshold. Once enough same-runner history exists, a separate change can add noise-aware regression budgets.

## Same-run tools/list A/B for performance PRs

Pull requests whose branch starts with `perf/` also run an **independent,
non-blocking** `list_ab` job. It checks out `main` and the PR revision into
separate worktrees on the **same GitHub Actions runner**, overlays the same
256-tool HTTP server fixture into both, and compiles both in native release
mode with the same MoonBit toolchain.

It runs the order **main → candidate → candidate → main** (ABBA). Each slot
measures `tools/list` throughput and p95 latency at concurrency 1 and 8,
using a Node HTTP load driver for 6 seconds per level, after warm-up. The
initial response must contain exactly 256 tools, and HTTP errors make the
comparison fail. The results, toolchain environment, and raw per-slot JSON
are uploaded as `perf-tool-list-abba` artifacts, with a GitHub Step Summary.

Unlike independent per-commit GitHub-hosted runner observations, this is a
more useful within-run before/after comparison. It still has noise, only two
measurements per side, and measures only the 256-tool list workload rather
than all MCP operations. Avoid interpreting a small delta as definitive.
