# MCP client and host example

This native executable demonstrates a high-level `MCPHost` that connects to
multiple MCP servers, discovers tools, and calls `local.echo`.

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

The STDIO connection should print `[local] connected`, and the
`local.echo` tool call should return the echoed text. The example also
attempts to connect to `http://localhost:4240/mcp`; that remote endpoint
is optional. If no HTTP MCP server is running there, a `[remote] failed`
message is expected and does not imply the local STDIO connection failed.

The root [`moon.work`](../../moon.work) includes the client, server, and
local JSON Schema module. The example's `moon.mod` declares the same
`colmugx/mcp@0.18.0` version as the repository release.

For the server's implementation, see
[`../server/cmd/main/main.mbt`](../server/cmd/main/main.mbt).
