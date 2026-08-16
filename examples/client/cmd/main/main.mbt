///| MCP Host Example using the high-level 2026-07-28 API.

///|
async fn main {
  let host = @client.MCPHost::MCPHost(name="example-host", version="1.0.0")

  @async.with_task_group(group => {
    match
      host.connect_stdio(
        name="local",
        cmd="moon",
        args=["run", "../server/cmd/main"],
        group~,
      ) {
      Ok(_) => println("[local] connected")
      Err(e) => println("[local] failed: \{e.message()}")
    }

    match host.connect_http(name="remote", url="http://localhost:4240/mcp") {
      Ok(_) => println("[remote] connected")
      Err(e) => println("[remote] failed: \{e.message()}")
    }

    match host.list_tools() {
      Ok(result) => {
        println("\{result.tools.length()} tools:")
        for tool in result.tools {
          println("  - \{tool.name}: \{tool.description}")
        }
      }
      Err(e) => println("[tools/list] error: \{e.message()}")
    }

    match host.call_tool("local.echo", arguments="{\"text\":\"hello\"}") {
      Ok(result) => println("[local.echo] \{@debug.to_string(result)}")
      Err(e) => println("[local.echo] error: \{e.message()}")
    }

    host.close_all()
  })
}
