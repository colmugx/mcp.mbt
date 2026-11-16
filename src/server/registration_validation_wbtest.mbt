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
    Ok(@tool.Complete(@tool.ToolResult::text("z")))
  })
  registry.register("a", "second", { "type": "object" }, fn(_, _) {
    Ok(@tool.Complete(@tool.ToolResult::text("a")))
  })
  let first = registry.list_tools()
  assert_eq(first.map(fn(tool) { tool.name }), ["a", "z"])
  // The caller can mutate the returned array without affecting future lists.
  first.push(first[0])
  assert_eq(registry.list_tools().map(fn(tool) { tool.name }), ["a", "z"])
  registry.register("m", "third", { "type": "object" }, fn(_, _) {
    Ok(@tool.Complete(@tool.ToolResult::text("m")))
  })
  assert_eq(registry.list_tools().map(fn(tool) { tool.name }), ["a", "m", "z"])
  registry.register("a", "replacement", { "type": "object" }, fn(_, _) {
    Ok(@tool.Complete(@tool.ToolResult::text("new")))
  })
  let final_list = registry.list_tools()
  assert_eq(final_list.map(fn(tool) { tool.name }), ["a", "m", "z"])
  assert_eq(final_list[0].description, Some("replacement"))
  assert_eq(registry.list_tools(), final_list)
}

///|
test "tool wire JSON cache follows registrations and replacements" {
  let registry = ToolRegistry::ToolRegistry()
  assert_eq(registry.list_tool_jsons(), ([] : Array[Json]))
  registry.register("z", "first", { "type": "object" }, fn(_, _) {
    Ok(@tool.Complete(@tool.ToolResult::text("z")))
  })
  registry.register("a", "second", { "type": "object" }, fn(_, _) {
    Ok(@tool.Complete(@tool.ToolResult::text("a")))
  })
  let expected = registry.list_tools().map(@types.ToolDefinition::to_json)
  assert_eq(registry.list_tool_jsons(), expected)
  assert_eq(registry.list_tool_jsons(), expected)
  registry.register("m", "third", { "type": "object" }, fn(_, _) {
    Ok(@tool.Complete(@tool.ToolResult::text("m")))
  })
  let after_insert = registry.list_tools().map(@types.ToolDefinition::to_json)
  assert_eq(registry.list_tool_jsons(), after_insert)
  registry.register("a", "replacement", { "type": "object" }, fn(_, _) {
    Ok(@tool.Complete(@tool.ToolResult::text("new")))
  })
  let after_replace = registry.list_tools().map(@types.ToolDefinition::to_json)
  assert_eq(registry.list_tool_jsons(), after_replace)
  let caller_array = registry.list_tool_jsons()
  caller_array.push(Json::null())
  assert_eq(registry.list_tool_jsons(), after_replace)
  assert_eq(registry.list_tool_jsons()[0], after_replace[0])
  // Previously materialized snapshots still contain the earlier description.
  guard expected[0] is { "description": String(description), .. } else {
    fail("expected old tool description")
  }
  assert_eq(description, "second")
}
