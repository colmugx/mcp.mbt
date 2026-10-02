# 7. Host Guide

`MCPHost` is the high-level API for applications that connect to several MCP servers at once — aggregate their tools, then call them through one object.

All snippets assume:

```moonbit
import {
  "colmugx/mcp",
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
match host.connect_http(name="remote", url="http://localhost:4240/mcp") {
  Ok(_) => println("[remote] connected")
  Err(e) => println("[remote] failed: \{e.message()}")
}
```

```moonbit
@async.with_task_group(group => {
  match
    host.connect_stdio(
      name="local",
      cmd="moon",
      args=["run", "server"],
      group~,
    ) {
    Ok(_) => println("[local] connected")
    Err(e) => println("[local] failed: \{e.message()}")
  }
})
```

Connection names must be unique within a host. They become the prefix for routed tool names.

## List tools

```moonbit
match host.list_tools() {
  Ok(result) =>
    for tool in result.tools {
      println("\{tool.name}: \{tool.description}")
    }
  Err(e) => println(e.message())
}
```

If `local` and `remote` both expose `echo`, the host returns `local.echo` and `remote.echo`.

## Call tools

```moonbit
match host.call_tool("local.echo", arguments="{\"text\":\"hello\"}") {
  Ok(result) => println(@debug.to_string(result))
  Err(e) => println(e.message())
}
```

Unqualified names are rejected because they are ambiguous.

## Close

```moonbit
host.close_all()
```

`close_all` closes every client connection and clears the host connection map.
