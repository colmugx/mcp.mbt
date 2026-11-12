///|
/// Minimal MCP client for the Streamable HTTP server in `cmd/server`.
///
/// `connect_http` performs transport setup plus `server/discover`; there is no
/// separate initialize step. Every call returns its value directly and raises
/// `MCPError` on failure.
///
/// Run the server first, then `moon run cmd/client` from `examples/http`.

///|
#warnings("-cancellable_defer")
async fn main {
  let client = @mcp.MCPClient::connect_http(
    url="http://127.0.0.1:4240/mcp",
    name="http-example-client",
    version="1.0.0",
  )
  defer @async.protect_from_cancel(() => client.close())
  let discovery = client.discover_result()
  println("supported versions: \{discovery.supported_versions.join(", ")}")
  let tools = client.list_tools()
  println("tools: \{tools.tools.map(fn(tool) { tool.name }).join(", ")}")
  for block in client.call_tool("now", arguments="{}").content {
    match block {
      @mcp.ContentBlock::Text(text, ..) => println("now: \{text}")
      _ => ()
    }
  }
  for
    block in client.call_tool("reverse", arguments="{\"text\":\"stressed\"}").content {
    match block {
      @mcp.ContentBlock::Text(text, ..) => println("reverse: \{text}")
      _ => ()
    }
  }
}
