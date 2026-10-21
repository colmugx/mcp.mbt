///| MCP Host Example using the high-level 2026-07-28 API.

///|
async fn main {
  let host = @client.MCPHost::MCPHost(name="example-host", version="1.0.0")

  @async.with_task_group(group => {
    defer host.close_all()
    try
      host.connect_stdio(
        name="local",
        cmd="moon",
        args=["run", "../server/cmd/main"],
        group~,
      )
    catch {
      @types.MCPError::_ as e => println("[local] failed: \{e.message()}")
      error => raise error
    } noraise {
      _ => println("[local] connected")
    }

    try
      host.connect_http(name="remote", url="http://localhost:4240/mcp")
    catch {
      @types.MCPError::_ as e => println("[remote] failed: \{e.message()}")
      error => raise error
    } noraise {
      _ => println("[remote] connected")
    }

    try host.list_tools() catch {
      @types.MCPError::_ as e => println("[tools/list] error: \{e.message()}")
      error => raise error
    } noraise {
      result => {
        println("\{result.tools.length()} tools:")
        for tool in result.tools {
          let description = tool.description.unwrap_or("")
          println("  - \{tool.name}: \{description}")
        }
      }
    }

    try host.call_tool("local.echo", arguments="{\"text\":\"hello\"}") catch {
      @types.MCPError::_ as e => println("[local.echo] error: \{e.message()}")
      error => raise error
    } noraise {
      result => println("[local.echo] \{@debug.to_string(result)}")
    }
  })
}
