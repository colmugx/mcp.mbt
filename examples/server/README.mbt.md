# MCP STDIO server example

This native executable provides an MCP server with two tools:
`echo(text)` (returns the supplied text) and `add(a, b)`
(returns their sum).

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
as its STDIO child process and invokes `local.echo`, so no second
terminal is required.

The root [`moon.work`](../../moon.work) makes both example modules
and the JSON Schema submodule available in the same workspace.
