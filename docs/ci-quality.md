# Non-blocking MCP quality CI

The SDK quality workflow is intentionally separate from the existing code-check workflow. It runs on pull requests, pushes to main, and manual dispatches. Both jobs use GitHub Actions job-level continue-on-error, so conformance or benchmark failures never block the existing checks or merges.

## Protocol correctness

The workflow uses the official modelcontextprotocol/conformance runner against small MoonBit fixtures.

Server smoke scenarios:

- server-stateless
- tools-list
- tools-call-simple-text

Client smoke scenarios:

- tools_call
- request-metadata

This is an initial, deliberately small protocol smoke suite, not a claim of complete MCP conformance. The existing MoonBit unit and integration tests remain in the regular check workflow. As the adapters grow, add scenarios here and move known failures into an explicit expected-failures baseline rather than silently skipping them.

## Throughput

The throughput job records two complementary measurements against the same MoonBit HTTP server:

1. A native MoonBit MCPClient drives the MoonBit MCPServer at concurrency 1, 4, 16, and 64, with 500 tool calls per worker. Each JSONL record includes request count, elapsed time, achieved requests per second, and errors.
2. MCP Inspector's mcpdo load mode measures server-facing end-to-end throughput at concurrency 1, 4, 16, and 64, with a warm-up and a fixed duration per stage.

The Inspector is only the load generator; results are not used to rank programming languages. The MoonBit-to-MoonBit measurement gives a direct SDK round-trip signal, while the Inspector run provides a second, independently implemented load driver.

Both jobs upload raw logs and environment details as workflow artifacts. The workflow currently records results rather than enforcing a performance threshold. Once enough same-runner history exists, a separate change can add noise-aware regression budgets.
