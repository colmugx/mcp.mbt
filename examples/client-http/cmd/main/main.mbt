///|
/// HTTP MCP Client Example
///
/// Demonstrates connecting to a remote MCP server over HTTP (Streamable HTTP transport).
/// This example shows how a client would interact with an MCP server like the
/// GitHub MCP Server, filesystem server, or any HTTP-based MCP service.
///
/// NOTE: HttpClientTransport.send() is currently a stub (moonbitlang/async
/// does not yet provide an HTTP client). This example shows the intended API
/// and will work once the upstream HTTP client is available.
///
/// Expected usage when HTTP client is available:
///
///   moon run @client-http/cmd/main
///
async fn main {
  let client = @client.MCPClient::new(
    name="http-example-client",
    version="1.0.0",
  )

  // Connect to a remote MCP server via HTTP
  // Replace with your actual MCP server URL
  client.set_transport(
    @transport.AnyTransport::HttpClient(
      @transport.HttpClientTransport::new("http://localhost:4240/mcp"),
    ),
  )

  // Register notification callbacks
  client.on_tools_changed(fn() {
    println("[notification] server tools list changed")
  })
  client.on_resources_changed(fn() {
    println("[notification] server resources list changed")
  })

  // MCP initialization handshake
  match client.initialize() {
    Err(e) => {
      println("[error] Initialize failed: \{e.message()}")
      client.close()
      return
    }
    Ok(_) => println("[connected] server initialized")
  }

  // Discover available tools
  match client.list_tools() {
    Ok(tools_json) => println("[tools] \{tools_json}")
    Err(e) => println("[error] List tools failed: \{e.message()}")
  }

  // Call a tool - example: searching repositories (GitHub MCP Server style)
  // Adjust tool name and arguments to match your server's actual tools
  match
    client.call_tool("search", arguments="{\"query\":\"mcp server moonbit\"}") {
    Ok(result) => println("[search] \{result}")
    Err(e) => println("[error] Call search failed: \{e.message()}")
  }

  // List resources
  match client.list_resources() {
    Ok(resources_json) => println("[resources] \{resources_json}")
    Err(e) => println("[error] List resources failed: \{e.message()}")
  }

  // Read a specific resource
  match client.read_resource("file:///config.json") {
    Ok(content) => println("[resource] \{content}")
    Err(e) => println("[error] Read resource failed: \{e.message()}")
  }

  // List and get prompts
  match client.list_prompts() {
    Ok(prompts_json) => println("[prompts] \{prompts_json}")
    Err(e) => println("[error] List prompts failed: \{e.message()}")
  }

  // Set log level for debugging
  match client.set_log_level("debug") {
    Ok(_) => println("[log] level set to debug")
    Err(e) => println("[error] Set log level failed: \{e.message()}")
  }

  client.close()
}
