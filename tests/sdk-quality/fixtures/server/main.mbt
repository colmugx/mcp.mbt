///|
async fn main {
  let server = @mcp.MCPServer("mcp-conformance", "0.18.4")
    .tool(
      "test_simple_text",
      "Return a fixed text response for protocol conformance tests",
      { "type": "object", "properties": {} },
      fn(_context, _args) {
        Ok(
          @mcp.ToolResult::text(
            "This is a simple text response for testing.",
          ),
        )
      },
    )
    .tool(
      "bench_echo",
      "Echo a message for throughput measurements",
      {
        "type": "object",
        "properties": {
          "message": { "type": "string" },
        },
        "required": ["message"],
      },
      fn(_context, args) {
        let message = @mcp.get_string(args, "message").unwrap_or("")
        Ok(@mcp.ToolResult::text(message))
      },
    )
  server.run_http(port=3000, path="/mcp")
}
