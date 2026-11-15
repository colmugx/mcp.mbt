///|
/// Independent benchmark fixture: many tools make the cost of tools/list sorting
/// observable, without modifying the production benchmark fixtures.
async fn main {
  let server = @mcp.MCPServer("list-benchmark", "0.18.4")
  for i in 0..<256 {
    ignore(
      server.tool(
        "bench_tool_" + i.to_string(),
        "List benchmark tool " + i.to_string(),
        { "type": "object", "properties": {} },
        fn(_context, _args) { Ok(@mcp.ToolResult::text("ok")) },
      ),
    )
  }
  server.run_http(port=3000, path="/mcp")
}
