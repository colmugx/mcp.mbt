///|
fn validation_call(name : String, arguments : Json?) -> String {
  let params : Map[String, Json] = {
    "name": Json::string(name),
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientInfo": { "name": "test", "version": "1" },
      "io.modelcontextprotocol/clientCapabilities": {},
    },
  }
  if arguments is Some(value) {
    params["arguments"] = value
  }
  (
    {
      "jsonrpc": "2.0",
      "id": 1,
      "method": "tools/call",
      "params": Json::object(params),
    } : Json).stringify()
}

///|
async test "tool validation: local references, exact wire values and no invalid-input execution" {
  let calls = Ref(0)
  let definition = @types.ToolDefinition::from_json(
    @json.parse(
      "{\"name\":\"precise\",\"inputSchema\":{\"type\":\"object\",\"$defs\":{\"amount\":{\"type\":\"number\",\"multipleOf\":0.1},\"id\":{\"const\":9007199254740993}},\"properties\":{\"amount\":{\"$ref\":\"#/$defs/amount\"},\"id\":{\"$ref\":\"#/$defs/id\"}},\"required\":[\"amount\",\"id\"],\"additionalProperties\":false},\"outputSchema\":{\"type\":\"integer\",\"const\":9007199254740993}}",
    ),
  )
  let server = MCPServer::MCPServer("test", "1").tool_definition(definition, (
    _context,
    _,
  ) => {
    calls.val += 1
    Ok(
      @tool.Complete(
        @types.ToolResult::structured(@json.parse("9007199254740993")),
      ),
    )
  })
  for
    args in [
      "{\"amount\":0.31,\"id\":9007199254740993}", "{\"amount\":0.3,\"id\":9007199254740992}",
      "{\"amount\":0.30000000000000000000000000000000000001,\"id\":9007199254740993}",
      "{\"amount\":0.3,\"id\":9007199254740993,\"extra\":true}",
    ] {
    let response = @json.parse(
      server.handle_request(
        validation_call("precise", Some(@validation.parse_json(args))),
      ),
    )
    assert_true(
      response is { "error": { "code": -32602, .. }, .. },
      msg=args + " => " + response.stringify(),
    )
  }
  let missing = @json.parse(
    server.handle_request(validation_call("precise", None)),
  )
  assert_true(missing is { "error": { "code": -32602, .. }, .. })
  assert_eq(calls.val, 0)
  let response = @json.parse(
    server.handle_request(
      validation_call(
        "precise",
        Some(@json.parse("{\"amount\":0.3,\"id\":9007199254740993}")),
      ),
    ),
  )
  guard response is { "result": { "structuredContent": value, .. }, .. } else {
    fail("expected structured result")
  }
  assert_eq(value.stringify(), "9007199254740993")
  assert_eq(calls.val, 1)
}

///|
async test "tool validation: output presence, arbitrary JSON and explicit tool errors" {
  let result = Ref(@types.ToolResult::structured(Json::null()))
  let definition = @types.ToolDefinition::from_json({
    "name": "outputs",
    "inputSchema": { "type": "object" },
    "outputSchema": {
      "anyOf": [
        { "type": "null" },
        { "type": "integer" },
        { "type": "array", "items": { "type": "integer" } },
      ],
    },
  })
  let server = MCPServer::MCPServer("test", "1").tool_definition(definition, (
    _context,
    _,
  ) => Ok(@tool.Complete(result.val)))
  for value in [Json::null(), 3, [1, 2]] {
    result.val = @types.ToolResult::structured(value)
    let response = @json.parse(
      server.handle_request(validation_call("outputs", None)),
    )
    assert_true(response is { "result": { "structuredContent": _, .. }, .. })
  }
  for
    invalid in [
      @types.ToolResult::text("no structured content"),
      @types.ToolResult::structured(true),
    ] {
    result.val = invalid
    let response = @json.parse(
      server.handle_request(validation_call("outputs", None)),
    )
    assert_true(response is { "error": { "code": -32603, .. }, .. })
  }
  result.val = @types.ToolResult::error("ordinary tool failure")
  let response = @json.parse(
    server.handle_request(validation_call("outputs", None)),
  )
  assert_true(response is { "result": { "isError": true, .. }, .. })
}

///|
async test "tool validation: owned definition snapshot and failed replacement are atomic" {
  let properties : Map[String, Json] = { "x": { "type": "integer" } }
  let definition = @types.ToolDefinition::new(
    "owned",
    Json::object({
      "type": "object",
      "properties": Json::object(properties),
      "additionalProperties": false,
    }),
  )
  let registry = ToolRegistry::ToolRegistry()
  registry.register_definition(definition, (_context, _) => {
    Ok(@tool.Complete(@types.ToolResult::text("original")))
  })
  properties["x"] = { "type": "string" }
  guard registry.list_tools()[0].input_schema
    is { "properties": { "x": { "type": "integer", .. }, .. }, .. } else {
    fail("advertised schema mutated")
  }
  let invalid_schemas : Array[Json] = [
    {
      "type": "object",
      "properties": { "x": { "$ref": "https://example.com/schema" } },
    },
    { "type": "object", "required": "x" },
  ]
  for invalid in invalid_schemas {
    try
      registry.register_definition(
        @types.ToolDefinition::new("owned", invalid),
        (_context, _) => {
          Ok(@tool.Complete(@types.ToolResult::text("replacement")))
        },
      )
    catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("invalid schema registered")
    }
  }
  let context = @runtime.RequestContext::new(@types.RequestId::Int(1))
  assert_true(
    registry.call_tool("owned", context, { "x": "bad" })
    is Err(@types.InvalidParams(_)),
  )
  assert_true(
    registry.call_tool("owned", context, { "x": 1 })
    is Ok(@tool.Complete({ content: _, .. })),
  )
  assert_eq(registry.list_tools().length(), 1)
}
