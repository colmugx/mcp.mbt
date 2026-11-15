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
  try
    registry.call_tool(
      "unknown",
      @runtime.RequestContext::new(@types.RequestId::Int(1)),
      Json::object({}),
    )
  catch {
    @types.InvalidParams(_) => ()
    error => raise error
  } noraise {
    _ => fail("unknown tools must report InvalidParams")
  }
}


///|
test "tool list cache invalidates on insertion and replacement" {
  let registry = ToolRegistry::ToolRegistry()
  assert_eq(registry.list_tools().length(), 0)
  registry.register("z", "first", { "type": "object" }, fn(_, _) {
    Ok(@tool.ToolResult::text("z"))
  })
  registry.register("a", "second", { "type": "object" }, fn(_, _) {
    Ok(@tool.ToolResult::text("a"))
  })
  let first = registry.list_tools()
  assert_eq(first.map(fn(tool) { tool.name }), ["a", "z"])
  // The caller can mutate the returned array without affecting future lists.
  first.push(first[0])
  assert_eq(registry.list_tools().map(fn(tool) { tool.name }), ["a", "z"])
  registry.register("m", "third", { "type": "object" }, fn(_, _) {
    Ok(@tool.ToolResult::text("m"))
  })
  assert_eq(registry.list_tools().map(fn(tool) { tool.name }), ["a", "m", "z"])
  registry.register("a", "replacement", { "type": "object" }, fn(_, _) {
    Ok(@tool.ToolResult::text("new"))
  })
  let final_list = registry.list_tools()
  assert_eq(final_list.map(fn(tool) { tool.name }), ["a", "m", "z"])
  assert_eq(final_list[0].description, Some("replacement"))
  assert_eq(registry.list_tools(), final_list)
}
