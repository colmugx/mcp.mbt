///|
async fn main {
  let args = @env.args()
  guard args.length() > 1 else {
    panic()
  }
  let server_url = args[args.length() - 1]
  let scenario = @env.get_env_var("MCP_CONFORMANCE_SCENARIO").unwrap_or("")

  let client = @mcp.MCPClient::connect_http(
    url=server_url,
    name="colmugx-mcp-conformance-client",
    version="0.18.4",
  )
  defer @async.protect_from_cancel(() => client.close())

  match scenario {
    "tools_call" => {
      ignore(client.list_tools())
      ignore(
        client.call_tool(
          "add_numbers",
          arguments="{\"a\":20,\"b\":22}",
        ),
      )
    }
    "request-metadata" => ignore(client.list_tools())
    _ => ignore(client.discover_result())
  }
}
