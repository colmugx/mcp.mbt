///|
test "tool registration rejects invalid wire schemas before adding the tool" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  for
    schema in [
      Json::object({}),
      Json::object({ "type": "array" }),
      Json::null(),
    ] {
    try
      server.tool("invalid", "Invalid tool", schema, fn(_context, _) {
        Ok(@tool.ToolResult::text("must not execute"))
      })
    catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("registration must reject an invalid tool definition")
    }
    assert_eq(server.registry.list_tools().length(), 0)
  }
}

///|
async test "unknown tool returns invalid params" {
  let registry = ToolRegistry::ToolRegistry()
  match
    registry.call_tool(
      "unknown",
      @runtime.RequestContext::new(@types.RequestId::Int(1)),
      Json::object({}),
    ) {
    Err(@types.InvalidParams(_)) => ()
    _ => fail("unknown tools must report InvalidParams")
  }
}
