///|
/// MCP Host Example
///
/// Demonstrates connecting to multiple MCP servers simultaneously:
/// - A local server via stdio (the examples/server)
/// - A remote server via HTTP
///
/// Usage with local stdio server:
///
///   moon run @client/cmd/main | moon run ../server/cmd/main
///
/// Or use as a host connecting to multiple servers (HTTP requires upstream HTTP client).
///
/// NOTE: HttpClientTransport.send() is currently a stub (moonbitlang/async
/// does not yet provide an HTTP client). The HTTP connection shows the intended API.
///

///|
struct HostConnection {
  name : String
  client : @client.MCPClient
  server_info : @types.ServerInfo
}

///|
fn HostConnection::new(
  name~ : String,
  client~ : @client.MCPClient,
  server_info~ : @types.ServerInfo,
) -> HostConnection {
  { name, client, server_info }
}

///|
/// Connect to an MCP server and return the connection on success.
///
async fn connect(
  host_name : String,
  host_version : String,
  server_name : String,
  transport : @transport.AnyTransport,
) -> Result[HostConnection, @types.MCPError] {
  let client = @client.MCPClient::new(
    name=host_name,
    version=host_version,
    transport~,
  )
  match client.initialize() {
    Err(e) => {
      client.close()
      Err(e)
    }
    Ok(server_info) =>
      Ok(HostConnection::new(name=server_name, client~, server_info~))
  }
}

///|
/// Aggregate tools from all connections.
///
async fn list_all_tools(
  connections : Array[HostConnection],
) -> Array[(String, @client.ListToolsResult)] {
  let results : Array[(String, @client.ListToolsResult)] = []
  for conn in connections {
    match conn.client.list_tools() {
      Ok(result) => results.push((conn.name, result))
      Err(_) => ()
    }
  }
  results
}

///|
async fn main {
  let host_name = "example-host"
  let host_version = "1.0.0"
  let connections : Array[HostConnection] = []

  // Connection 1: local stdio server
  // Usage: moon run @client/cmd/main | moon run ../server/cmd/main
  let stdio_transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::new(),
  )
  match connect(host_name, host_version, "local-stdio", stdio_transport) {
    Ok(conn) => {
      println(
        "[stdio] Connected to \{conn.server_info.name} v\{conn.server_info.version}",
      )
      connections.push(conn)
    }
    Err(e) => println("[stdio] Failed: \{e.message()}")
  }

  // Connection 2: remote HTTP server
  // NOTE: HttpClientTransport is a stub until moonbitlang/async provides HTTP client
  let http_transport = @transport.AnyTransport::HttpClient(
    @transport.HttpClientTransport::new("http://localhost:4240/mcp"),
  )
  match connect(host_name, host_version, "remote-http", http_transport) {
    Ok(conn) => {
      println(
        "[http] Connected to \{conn.server_info.name} v\{conn.server_info.version}",
      )
      connections.push(conn)
    }
    Err(e) => println("[http] Failed: \{e.message()}")
  }

  if connections.length() == 0 {
    println("[error] No servers connected, exiting")
    return
  }

  // Aggregate and display tools from all servers
  let all_tools = list_all_tools(connections)
  for entry in all_tools {
    let (name, result) = entry
    println("[\{name}] \{result.tools.length()} tools:")
    for tool in result.tools {
      println("  - \{tool.name}: \{tool.description}")
    }
  }

  // Call tools on specific connections
  for conn in connections {
    match
      conn.client.call_tool(
        "echo",
        arguments="{\"text\":\"Hello from \{conn.name}!\"}",
      ) {
      Ok(result) => println("[\{conn.name}/echo] \{result}")
      Err(e) => println("[\{conn.name}/echo] Error: \{e.message()}")
    }

    match conn.client.ping() {
      Ok(_) => println("[\{conn.name}/ping] alive")
      Err(e) => println("[\{conn.name}/ping] Error: \{e.message()}")
    }
  }

  // Cleanup all connections
  for conn in connections {
    conn.client.close()
  }
}
