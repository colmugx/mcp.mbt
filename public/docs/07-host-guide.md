# 7. Host Guide

`MCPHost` is the high-level API for applications that connect to several MCP servers at once — aggregate their tools, then call them through one object.

All snippets assume:

```moonbit
import {
  "colmugx/mcp",
  "colmugx/mcp/client",
  "moonbitlang/async",
  "moonbitlang/core/debug",
}
```

## Create

```moonbit
let host = @mcp.MCPHost(name="my-host", version="1.0.0")
```

## Connect

```moonbit
host.connect_http(name="remote", url="http://localhost:4240/mcp")
println("[remote] connected")
```

```moonbit
@async.with_task_group(group => {
  host.connect_stdio(
    name="local",
    cmd="moon",
    args=["run", "server"],
    group~,
  )
  println("[local] connected")
  // Make local calls while this group is alive.
})
```

Host operations raise on failure; they do not return Result. See the
[client error-handling guide](05-client-guide.md#error-handling).
Use unique connection names without `.`: they become the prefix for routed tool names, and the first dot separates the connection from the tool. Keep the task group used by `connect_stdio` alive for the entire period in which you make calls; leaving that group ends its child-process tasks.

Both connect methods accept `era?`: `ProtocolEra::Auto` probes modern discovery and permits legacy fallback, `Modern` rejects fallback, and `Legacy` skips the modern probe. Select `Modern` when your application relies on MRTR and MCP 2026-07-28 semantics.

## List tools

```moonbit
let result = host.list_tools()
for tool in result.tools {
  println("\{tool.name}: \{tool.description.unwrap_or(\"\")}")
}
```

If `local` and `remote` both expose `echo`, the host returns `local.echo` and `remote.echo`.

The aggregate is not a response from a single server: it has no shared TTL or cache scope. Per-connection result metadata and pagination cursors are retained under `result.metadata.extensions["dev.moonbit.mcp/hostSources"]`. Each connection entry contains `metadata` and, when present, `nextCursor`. Inspect source cursors when checking whether you have retrieved a complete inventory; the host currently requests one page per connection rather than inventing an aggregate cursor.

## Call tools

```moonbit
let result = host.call_tool("local.echo", arguments="{\"text\":\"hello\"}")
println(@debug.to_string(result))
```

Unqualified names are rejected because they are ambiguous.

## Close

```moonbit
host.close_all()
```

`close_all` closes every client connection and clears the host connection map.
