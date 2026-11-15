///|
/// In-process list-heavy request benchmark (no HTTP or external load process).
/// Both main and candidate compile this exact same fixture on the same runner.
async fn main {
  let server = @mcp.MCPServer("microbench", "0.18.4")
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
  let request : Json = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list",
    "params": {
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
      },
    },
  }
  let wire = request.stringify()
  let sample = server.handle_request(wire)
  if !sample.contains("bench_tool_0") {
    panic()
  }

  for _ in 0..<100 {
    ignore(server.handle_request(wire))
  }
  let repetitions = 5000
  let started = @env.now()
  let mut total_bytes = 0
  for _ in 0..<repetitions {
    let response = server.handle_request(wire)
    total_bytes += response.length()
  }
  let elapsed_ms = (@env.now() - started).to_double()
  let rps = if elapsed_ms > 0.0 {
    repetitions.to_double() * 1000.0 / elapsed_ms
  } else {
    0.0
  }
  println(
    "{\"requests\":\{repetitions},\"elapsed_ms\":\{elapsed_ms},\"rps\":\{rps},\"total_bytes\":\{total_bytes}}",
  )
}
