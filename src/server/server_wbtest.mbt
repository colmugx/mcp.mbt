///| Server and Registry Integration Tests

///| Tests for MCPServer and ToolRegistry (simplified)

///|
/// MCPServer Tests
test "MCPServer::MCPServer creates server with name and version" {
  let server = MCPServer::MCPServer("test-server", "1.0.0")
  @debug.assert_eq(server.name, "test-server")
  @debug.assert_eq(server.version, "1.0.0")
}

///|
test "MCPServer::MCPServer creates empty registry" {
  let server = MCPServer::MCPServer("test-server", "1.0.0")
  @debug.assert_eq(server.registry.list_tools().length(), 0)
}

///|
test "MCPServer register_tool adds to registry" {
  let server = MCPServer::MCPServer("test-server", "1.0.0")
  server.register_tool(
    "test_tool",
    "Test description",
    Json::object({ "type": "object" }),
    fn(_args) { Ok(@tool.ToolResult::text("test")) },
  )
  @debug.assert_eq(server.registry.list_tools().length(), 1)
  @debug.assert_eq(server.registry.list_tools()[0].name, "test_tool")
}

///|
test "MCPServer register_tool preserves order" {
  let server = MCPServer::MCPServer("test-server", "1.0.0")
  server.register_tool("tool1", "First tool", Json::object({}), fn(_args) {
    Ok(@tool.ToolResult::text("test1"))
  })
  server.register_tool("tool2", "Second tool", Json::object({}), fn(_args) {
    Ok(@tool.ToolResult::text("test2"))
  })
  @debug.assert_eq(server.registry.list_tools().length(), 2)
  @debug.assert_eq(server.registry.list_tools()[0].name, "tool1")
  @debug.assert_eq(server.registry.list_tools()[1].name, "tool2")
}

///|
test "MCPServer tool metadata is stored correctly" {
  let server = MCPServer::MCPServer("test-server", "1.0.0")
  let schema = Json::object({
    "type": "object",
    "properties": { "value": { "type": "string", "description": "Test value" } },
  })
  server.register_tool("test", "Test tool description", schema, fn(_args) {
    Ok(@tool.ToolResult::text("test"))
  })
  let tool_entry = server.registry.list_tools()[0]
  @debug.assert_eq(tool_entry.name, "test")
  @debug.assert_eq(tool_entry.description, "Test tool description")
  @debug.assert_eq(tool_entry.input_schema, schema)
}

///| =====================================================

///| ToolRegistry Tests

///|
/// =====================================================
test "ToolRegistry::ToolRegistry creates empty registry" {
  let registry = ToolRegistry::ToolRegistry()
  @debug.assert_eq(registry.list_tools().length(), 0)
}

///|
test "ToolRegistry::register adds tool entry" {
  let registry = ToolRegistry::ToolRegistry()
  registry.register(
    "test_tool",
    "Test tool description",
    Json::object({ "type": "object" }),
    fn(_args) { Ok(@tool.ToolResult::text("test")) },
  )
  @debug.assert_eq(registry.list_tools().length(), 1)
  @debug.assert_eq(registry.list_tools()[0].name, "test_tool")
  @debug.assert_eq(
    registry.list_tools()[0].description,
    "Test tool description",
  )
}

///|
test "ToolRegistry::list_tools returns tool definitions" {
  let registry = ToolRegistry::ToolRegistry()
  registry.register("tool1", "Description 1", Json::object({}), fn(_args) {
    Ok(@tool.ToolResult::text("test"))
  })
  registry.register("tool2", "Description 2", Json::object({}), fn(_args) {
    Ok(@tool.ToolResult::text("test"))
  })
  let tools = registry.list_tools()
  @debug.assert_eq(tools.length(), 2)
  @debug.assert_eq(tools[0].name, "tool1")
  @debug.assert_eq(tools[0].description, "Description 1")
  @debug.assert_eq(tools[1].name, "tool2")
  @debug.assert_eq(tools[1].description, "Description 2")
}

///|
test "ToolRegistry preserves input schemas" {
  let registry = ToolRegistry::ToolRegistry()
  let schema = Json::object({
    "type": "object",
    "properties": { "value": { "type": "string" } },
  })
  registry.register("test", "Test tool", schema, fn(_args) {
    Ok(@tool.ToolResult::text("test"))
  })
  @debug.assert_eq(registry.list_tools()[0].input_schema, schema)
}

///|
test "ToolRegistry::list_tools includes all metadata" {
  let registry = ToolRegistry::ToolRegistry()
  let schema = Json::object({ "type": "object", "properties": {} })
  registry.register("my_tool", "My tool description", schema, fn(_args) {
    Ok(@tool.ToolResult::text("result"))
  })
  let tools = registry.list_tools()
  @debug.assert_eq(tools.length(), 1)
  let tool = tools[0]
  @debug.assert_eq(tool.name, "my_tool")
  @debug.assert_eq(tool.description, "My tool description")
  @debug.assert_eq(tool.input_schema, schema)
}

///| =====================================================

///| Example: Complete Server Setup

///|
/// =====================================================
test "example: register multiple tools and verify" {
  let server = MCPServer::MCPServer("multi-tool-server", "1.0.0")

  // Register multiple tools
  server.register_tool("tool_a", "Tool A description", Json::object({}), fn(
    _args,
  ) {
    Ok(@tool.ToolResult::text("A"))
  })
  server.register_tool("tool_b", "Tool B description", Json::object({}), fn(
    _args,
  ) {
    Ok(@tool.ToolResult::text("B"))
  })
  server.register_tool("tool_c", "Tool C description", Json::object({}), fn(
    _args,
  ) {
    Ok(@tool.ToolResult::text("C"))
  })

  // Verify server metadata
  @debug.assert_eq(server.name, "multi-tool-server")
  @debug.assert_eq(server.version, "1.0.0")

  // Verify all tools are registered
  @debug.assert_eq(server.registry.list_tools().length(), 3)

  // Verify tool order is preserved
  @debug.assert_eq(server.registry.list_tools()[0].name, "tool_a")
  @debug.assert_eq(server.registry.list_tools()[1].name, "tool_b")
  @debug.assert_eq(server.registry.list_tools()[2].name, "tool_c")

  // Verify list_tools returns correct metadata
  let tools = server.registry.list_tools()
  @debug.assert_eq(tools.length(), 3)
  @debug.assert_eq(tools[0].name, "tool_a")
  @debug.assert_eq(tools[1].name, "tool_b")
  @debug.assert_eq(tools[2].name, "tool_c")
}

///|
test "example: server with complex schemas" {
  let server = MCPServer::MCPServer("complex-server", "1.0.0")
  let complex_schema = Json::object({
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "Search query" },
      "limit": { "type": "number", "description": "Result limit" },
      "filters": { "type": "array", "description": "Filter options" },
    },
    "required": Json::array([Json::string("query")]),
  })
  server.register_tool(
    "search",
    "Search with complex parameters",
    complex_schema,
    fn(_args) { Ok(@tool.ToolResult::text("search results")) },
  )

  // Verify schema is preserved
  let tool = server.registry.list_tools()[0]
  @debug.assert_eq(tool.name, "search")
  @debug.assert_eq(tool.description, "Search with complex parameters")

  // Verify schema structure
  match tool.input_schema {
    Object(map) => {
      match map.get("type") {
        Some(String("object")) => ()
        _ => panic()
      }
      match map.get("properties") {
        Some(Object(_)) => ()
        _ => panic()
      }
      match map.get("required") {
        Some(Array(_)) => ()
        _ => panic()
      }
    }
    _ => panic()
  }
}

///| =====================================================

///| Auth Builder Tests

///|
/// =====================================================
test "MCPServer::with_auth sets auth_config" {
  let server = MCPServer::MCPServer("auth-server", "1.0.0")
  match server.auth_config {
    None => ()
    Some(_) => panic()
  }
  let authed = server.with_auth(
    @transport.AuthConfig::AuthConfig(
      verify_token=fn(token) { token == "valid" },
      resource_metadata_url="http://localhost:4240/mcp",
    ),
  )
  match authed.auth_config {
    Some(config) =>
      @debug.assert_eq(
        config.resource_metadata_url,
        "http://localhost:4240/mcp",
      )
    None => panic()
  }
}

///|
test "MCPServer::with_auth preserves other fields" {
  let server = MCPServer::MCPServer("test", "1.0.0")
    .with_title("My Server")
    .with_description("A test server")
    .with_auth(
      @transport.AuthConfig::AuthConfig(
        verify_token=fn(_) { true },
        resource_metadata_url="http://localhost:4240/mcp",
      ),
    )
  @debug.assert_eq(server.name, "test")
  @debug.assert_eq(server.version, "1.0.0")
  @debug.assert_eq(server.title, Some("My Server"))
  @debug.assert_eq(server.description, Some("A test server"))
  match server.auth_config {
    Some(_) => ()
    None => panic()
  }
}
