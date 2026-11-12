# 1. Quickstart

This SDK implements the MCP protocol (revision 2026-07-28) in MoonBit. Most applications need exactly three types, all re-exported by the root facade `colmugx/mcp`:

- `MCPServer` — expose tools, resources, and prompts over stdio or HTTP.
- `MCPClient` — talk to one MCP server.
- `MCPHost` — coordinate several named client connections.

## Before you start

Add the dependencies (the async runtime is required for anything that connects):

```bash
moon add colmugx/mcp
moon add moonbitlang/async
```

Give your main package a `moon.pkg`:

```moonbit
import {
  "colmugx/mcp",
  "moonbitlang/async",
  "moonbitlang/core/debug",
  "moonbitlang/core/json",
}

pkgtype(kind: "executable")

supported_targets = "native"
```

> `moonbitlang/core/json` is needed for the `Json` values that public signatures
> and handler bodies use. stdio transport and the HTTP server run on native (and
> wasm); the HTTP client runs on js, and a js stdio client is available too. See
> the [transport reference](04-transport-reference.md) for the target matrix.

## Server

```moonbit
///|
async fn main {
  @mcp.MCPServer("notes", "1.0.0")
  .with_instructions("A tiny demo server.")
  .tool("echo", "Echo text back", Json::object({ "type": "object" }), fn(_context, args) {
    match @mcp.get_string(args, "text") {
      Ok(text) => Ok(@mcp.ToolResult::text(text))
      Err(e) => Ok(e) // e is the ready-made error ToolResult
    }
  })
  .run_stdio()
}
```

Run it with `moon run cmd/main` (or whatever your main package is called), then talk to it from any MCP client.

Prefer HTTP? Replace the last line with:

```moonbit
.run_http(port=4240, path="/mcp")
```

## Client

```moonbit
///|
async fn main {
  let client = @mcp.MCPClient::connect_http(
    url="http://localhost:4240/mcp",
    name="quickstart-client",
    version="1.0.0",
  )
  defer client.close()
  let result = client.call_tool("echo", arguments="{\"text\":\"hello\"}")
  for block in result.content { println(@debug.to_string(block)) }
}
```

Failures raise checked errors rather than returning `Err`. See the
[client error-handling guide](05-client-guide.md#error-handling) for local recovery.

For a local child-process server, wrap the connection in a task group — the child process belongs to async supervision:

```moonbit
@async.with_task_group(group => {
  let client = @mcp.MCPClient::connect_stdio(
    cmd="moon",
    args=["run", "server"],
    name="quickstart-client",
    version="1.0.0",
    group~,
  )
  defer client.close()
  // Make calls while this group is alive.
})
```
## Host

A host fans out to several servers and namespaces their tools as `connection.tool`:

```moonbit
///|
async fn main {
  let host = @mcp.MCPHost(name="quickstart-host", version="1.0.0")
  @async.with_task_group(group => {
    defer host.close_all()
    let _ = host.connect_stdio(
      name="local",
      cmd="moon",
      args=["run", "server"],
      group~,
    )
    let _ = host.connect_http(name="remote", url="http://localhost:4240/mcp")
    let _ = host.list_tools()
    let _ = host.call_tool("local.echo", arguments="{\"text\":\"hello\"}")
  })
}
```

If `local` and `remote` both expose `echo`, the host lists them as `local.echo` and `remote.echo`; unqualified names are rejected as ambiguous.

## Where to go next

- Register resources, prompts, and templates: [server guide](03-server-guide.md)
- All client methods, including era selection and subscriptions: [client guide](05-client-guide.md)
- Wire types such as `ContentBlock` and the error taxonomy: [protocol types](02-protocol-types.md)

## Runnable examples

The repository ships three native examples that are compiled by CI and cover
more than this quickstart:

| Example | Shows |
|---------|-------|
| [`examples/server`](../../examples/server/README.mbt.md) | stdio server: trait tools, structured output, MRTR elicitation + sampling, progress, cancellation, resources, prompts, completion |
| [`examples/client`](../../examples/client/README.mbt.md) | `MCPClient` feature tour plus `MCPHost` multi-server routing; starts the server example as a child process |
| [`examples/http`](../../examples/http/README.mbt.md) | Streamable HTTP server and client on port 4240 |
