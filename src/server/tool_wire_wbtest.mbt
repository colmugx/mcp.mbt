///|
async test "conformance: registry retains complete tool definition and result metadata" {
  let definition = @types.ToolDefinition::from_json({
    "name": "structured",
    "title": "Structured output",
    "inputSchema": { "type": "object", "additionalProperties": false },
    "outputSchema": { "type": "array", "items": { "type": "integer" } },
    "annotations": { "readOnlyHint": true },
    "icons": [],
    "_meta": { "com.example/tool": false },
    "com.example/definition": null,
  })
  let result = @types.ToolResult::from_json({
    "content": [],
    "structuredContent": [1, 2],
    "isError": false,
    "_meta": { "com.example/result": null },
    "com.example/output": false,
  })
  let server = MCPServer::MCPServer("test", "1").tool_definition(definition, (
    _context,
    _,
  ) => Ok(@tool.ToolCallOutcome::Complete(result)))
  assert_eq(server.registry.list_tools(), [definition])
  let list_response = @json.parse(
    handle_tools_list(server, @types.RequestId::Int(1)),
  )
  guard list_response is { "result": { "tools": Array(tools), .. }, .. } else {
    fail("expected tools list")
  }
  assert_eq(tools, [definition.to_json()])
  let request : Json = {
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "structured",
      "arguments": {},
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientInfo": {
          "name": "client",
          "version": "1",
        },
        "io.modelcontextprotocol/clientCapabilities": {},
      },
    },
  }
  let wire = @json.parse(server.handle_request(request.stringify()))
  guard wire is { "result": Object(fields), .. } else {
    fail("expected completed tool result")
  }
  let decoded = @types.ToolResult::from_json(Json::object(fields))
  assert_eq(decoded.structured_content, Some([1, 2]))
  assert_eq(
    decoded.metadata.meta.unwrap().get("com.example/result"),
    Some(null),
  )
  assert_eq(decoded.metadata.extensions.get("com.example/output"), Some(false))
  assert_eq(
    decoded.metadata.server_info(),
    Some({ "name": "test", "version": "1" }),
  )
  assert_eq(result.metadata.server_info(), None)
  assert_eq(result.metadata.result_type, None)
}

///|
test "conformance: server metadata merge does not mutate handler result" {
  let server = MCPServer::MCPServer("test", "1")
  let meta : Map[String, Json] = { "com.example/key": [null, false] }
  let fields : Map[String, Json] = {
    "content": [],
    "_meta": Json::object(meta),
  }
  let result = Json::object(fields)
  let original = result.stringify()
  let encoded = with_server_meta(server, result)
  assert_eq(result.stringify(), original)
  assert_eq(fields.get("resultType"), None)
  assert_eq(meta.get("io.modelcontextprotocol/serverInfo"), None)
  guard encoded is { "_meta": Object(output_meta), .. } else {
    fail("expected metadata")
  }
  assert_eq(output_meta.get("com.example/key"), Some([null, false]))
  assert_eq(
    output_meta.get("io.modelcontextprotocol/serverInfo"),
    Some({ "name": "test", "version": "1" }),
  )
  ignore(
    jsonrpc_cacheable_success_str(
      server,
      @types.RequestId::Int(1),
      result,
      0,
      "private",
    ),
  )
  assert_eq(result.stringify(), original)
}
