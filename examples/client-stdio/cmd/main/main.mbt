///|
/// Stdio MCP Client Example
///
/// This client connects to an MCP server through stdin/stdout.
/// To use, pipe this program's I/O to a running MCP server:
///
///   moon run @client-stdio/cmd/main | moon run @server/cmd/main
///
/// Or use with Claude Desktop / any MCP host that launches servers as child processes.
///
async fn main {
  let client = @client.MCPClient::new(
    name="stdio-example-client",
    version="1.0.0",
  )

  // Set transport to Stdio (reads from stdin, writes to stdout)
  client.set_transport(
    @transport.AnyTransport::Stdio(@transport.StdioTransport::new()),
  )

  // Register notification callbacks
  client.on_tools_changed(fn() {
    println("[notification] server tools list changed")
  })

  // Perform MCP initialization handshake
  match client.initialize() {
    Err(e) => {
      println("[error] Initialize failed: \{e.message()}")
      client.close()
      return
    }
    Ok(_) => println("[connected] server initialized")
  }

  // List available tools
  match client.list_tools() {
    Ok(tools_json) => println("[tools] \{tools_json}")
    Err(e) => println("[error] List tools failed: \{e.message()}")
  }

  // Call the "echo" tool
  match
    client.call_tool("echo", arguments="{\"text\":\"Hello from MoonBit!\"}") {
    Ok(result) => println("[echo] \{result}")
    Err(e) => println("[error] Call echo failed: \{e.message()}")
  }

  // Call the "add" tool
  match client.call_tool("add", arguments="{\"a\":12,\"b\":30}") {
    Ok(result) => println("[add] \{result}")
    Err(e) => println("[error] Call add failed: \{e.message()}")
  }

  // Ping the server
  match client.ping() {
    Ok(_) => println("[ping] server is alive")
    Err(e) => println("[error] Ping failed: \{e.message()}")
  }

  client.close()
}
