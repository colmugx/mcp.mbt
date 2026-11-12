# MCP client and host example

This native executable is a feature tour of the **client** API. It runs in two
phases.

## Phase 1 — one connection, every call type

`MCPClient::connect_stdio` starts [`../server`](../server/README.mbt.md) as a
child process and the example then exercises:

| Feature | What to look at |
|---------|-----------------|
| Capability discovery | `discover_result()` — supported versions, instructions |
| Plain tools | `echo` |
| Structured output | `stats` — prints `structuredContent` validated against the server's `output_schema` |
| Multi-round-trip (MRTR) | `review` — the server answers `input_required`; the registered `on_elicitation` and `on_sampling` handlers answer, and the SDK retries automatically |
| Progress notifications | `slow` — `on_notification` with `on_progress`, correlated by `progress_token` |
| Resources | `list_resources`, `read_resource("memo://greeting")`, `list_resource_templates` |
| Prompts | `list_prompts`, `get_prompt("summarize", …)` |
| Completion | `complete(ref_type="ref/resource", …)` |

Registering the elicitation and sampling handlers is what advertises those
client capabilities; the server's MRTR tool is rejected by a client that does
not handle them.

## Phase 2 — several servers behind one host

`MCPHost` connects the same stdio server plus an optional Streamable HTTP
server, and tool names come back qualified per connection
(`local.echo`, `remote.now`, …), so two servers may expose the same tool name.

## Run

Install the [MoonBit CLI](https://www.moonbitlang.com/download) and clone
this repository with its `external/json-schema` submodule. From the
repository root:

```sh
git submodule update --init --recursive
moon update
cd examples/client
moon run cmd/main
```

**Run from `examples/client`**, not the repository root: the host launches
`moon run ../server/cmd/main` as a child process, and this relative path
depends on the current working directory. You do **not** need to start the
STDIO server manually; the client launches it.

Phase 1 output looks like this (five `progress` lines appear between `review`
and `slow`):

```
supported versions: 2026-07-28
instructions: Start with tools/list, then try the review tool.
4 tools: echo, slow, stats, review
echo: is_error=false
  text: hello
stats: is_error=false
  structured: {"count":4,"sum":10,"mean":2.5}
review: is_error=false
  text: Approved. Sampling result: {...}
  progress 1/5 step 1 of 5
  ...
slow: is_error=false
  text: finished 5 steps
resource: memo://notes/1
resource: memo://greeting
template: memo://notes/{id}
prompt: summarize
completion suggestions: 1, 2, 3
```

The remote connection in phase 2 is optional: without an HTTP server on port
4240 the example prints `[remote] failed: … Connection refused` and continues
with the stdio connection. Start [`../http`](../http/README.mbt.md) first to
see `[remote] connected` and the `remote.now` / `remote.reverse` tools.

The root [`moon.work`](../../moon.work) includes the client, server, HTTP
example and local JSON Schema module. The example's `moon.mod` declares the same
`colmugx/mcp` version as the repository release.
