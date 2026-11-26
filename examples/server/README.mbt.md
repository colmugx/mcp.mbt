# MCP STDIO server example

This native executable is a feature tour of the **server** API over standard
input/output: it is the server half of the
[client/host example](../client/README.mbt.md).

| Feature | What to look at |
|---------|-----------------|
| Trait-based tool registration | `EchoTool` (`impl @mcp.Tool`) |
| Structured output with an `output_schema` | `stats` — the SDK verifies `structuredContent` before publishing it |
| Multi-round-trip (MRTR) | `review` — returns `input_required` with an elicitation form and a sampling request, then finishes on the retry using `context.input_responses` |
| Progress notifications and cancellation | `slow` — five `progress_reporter.report` steps, `cancellation_token.throw_if_cancelled()` each round |
| Resources | `memo://greeting`, `memo://notes/1` and the `memo://notes/{id}` template |
| Prompts | `summarize`, with one required argument |
| Completion | `completion/complete` suggestions for `memo://notes/{id}` |
| Server metadata | `with_title` / `with_description` / `with_instructions` |

`review` needs MRTR continuation state, so the server installs an
`AesGcmStateCodec` with a fixed example key. A real deployment takes that key
from its secret store and uses the same key on every instance that must accept
the same `requestState`.

## Run

Install the [MoonBit CLI](https://www.moonbitlang.com/download) and clone
this repository with submodules. From the repository root:

```sh
git submodule update --init --recursive
moon update
cd examples/server
moon run cmd/main
```

The program serves MCP over **standard input/output**, not HTTP. When
started directly it waits for a client to send MCP/JSON-RPC messages; it
is normal not to see a greeting or terminal output. Stop it with Ctrl+C.

For a complete interactive demonstration, use the
[client/host example](../client/README.mbt.md) instead. When launched
from `examples/client`, that client **automatically starts this server**
as its STDIO child process, so no second terminal is required.

The root [`moon.work`](../../moon.work) makes the example modules and the
JSON Schema submodule available in the same workspace.
