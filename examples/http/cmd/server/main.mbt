///|
/// Minimal MCP server over **Streamable HTTP** (2026-07-28).
///
/// `run_http` binds the port and serves JSON-RPC at `path`; requests are
/// `POST`s, and a request that needs server-sent events (progress, MRTR input)
/// answers with an SSE stream instead of one JSON body.
///
/// Start it with `moon run cmd/server` from `examples/http`, then run the
/// client in another terminal (`moon run cmd/client`).

///|
struct NowTool {}

///|
impl @mcp.Tool for NowTool with fn name(_) -> String {
  "now"
}

///|
impl @mcp.Tool for NowTool with fn description(_) -> String {
  "Return a fixed timestamp so the example stays deterministic"
}

///|
impl @mcp.Tool for NowTool with fn params(_) -> Array[@mcp.ParamDef] {
  []
}

///|
impl @mcp.Tool for NowTool with fn execute(_, _context, _args : Json) -> @mcp.ToolCallOutcome {
  @mcp.ToolCallOutcome::Complete(@mcp.ToolResult::text("2026-07-28T00:00:00Z"))
}

///|
async fn main {
  let server = @mcp.MCPServer("http-example", "1.0.0")
    .with_instructions("A single deterministic tool served over HTTP.")
    .with_tool(NowTool::{ })
    .tool(
      "reverse",
      "Reverse the given text",
      { "type": "object", "properties": { "text": { "type": "string" } } },
      fn(_context, args) {
        let text = @mcp.get_string(args, "text").unwrap_or("")
        let reversed = text
          .to_array()
          .rev()
          .map(fn(ch) { ch.to_string() })
          .join("")
        Ok(@mcp.ToolResult::text(reversed))
      },
    )
  println("serving MCP on http://127.0.0.1:4240/mcp")
  server.run_http(port=4240, path="/mcp")
}
