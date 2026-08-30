# Quickstart

v0.14 is centered on three high-level types: `MCPServer`, `MCPClient`, and `MCPHost`.

## Server

```moonbit
async fn main {
  @mcp.MCPServer("notes", "1.0.0")
    .tool("echo", "Echo text", Json::object({}), fn(args) {
      Ok(@tool.ToolResult::text(args.stringify()))
    })
    .run_stdio()
}
```

Use HTTP by replacing `.run_stdio()` with:

```moonbit
.run_http(port=4240, path="/mcp")
```

## Client

```moonbit
async fn main {
  match @mcp.MCPClient::connect_http(
    url="http://localhost:4240/mcp",
    name="quickstart-client",
    version="1.0.0",
  ) {
    Ok(client) => {
      ignore(client.list_tools())
      client.close()
    }
    Err(e) => println(e.message())
  }
}
```

For local servers:

```moonbit
@async.with_task_group(group => {
  match @mcp.MCPClient::connect_stdio(
    cmd="moon",
    args=["run", "server"],
    name="quickstart-client",
    version="1.0.0",
    group~,
  ) {
    Ok(client) => client.close()
    Err(e) => println(e.message())
  }
})
```

## Host

```moonbit
async fn main {
  let host = @mcp.MCPHost(name="quickstart-host", version="1.0.0")
  @async.with_task_group(group => {
    ignore(host.connect_stdio(name="local", cmd="moon", args=["run", "server"], group~))
    ignore(host.connect_http(name="remote", url="http://localhost:4240/mcp"))
    ignore(host.list_tools())
    ignore(host.call_tool("local.echo", arguments="{\"text\":\"hello\"}"))
    host.close_all()
  })
}
```

Tools returned by a host are qualified as `connection.tool`.
