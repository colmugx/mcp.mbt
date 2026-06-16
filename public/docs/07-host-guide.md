# Host Guide

`MCPHost` is the v0.14 high-level API for applications that connect to multiple MCP servers.

## Create

```moonbit
let host = @mcp.MCPHost::new(name="my-host", version="1.0.0")
```

## Connect

```moonbit
ignore(host.connect_http(name="remote", url="http://localhost:4240/mcp"))
```

```moonbit
@async.with_task_group(group => {
  ignore(host.connect_stdio(
    name="local",
    cmd="moon",
    args=["run", "server"],
    group~,
  ))
})
```

Connection names must be unique within a host. They become the prefix for routed tool names.

## List Tools

```moonbit
match host.list_tools() {
  Ok(result) => for tool in result.tools { println(tool.name) }
  Err(e) => println(e.message())
}
```

If `local` and `remote` both expose `echo`, the host returns `local.echo` and `remote.echo`.

## Call Tools

```moonbit
ignore(host.call_tool("local.echo", arguments="{\"text\":\"hello\"}"))
```

Unqualified names are rejected because they are ambiguous.

## Close

```moonbit
host.close_all()
```

`close_all` closes every client connection and clears the host connection map.
