///|
async test "tool schema resources: owned remote anchors, dialects and atomic replacement" {
  let resources : Map[String, Json] = {
    "https://schemas.example/count": {
      "$id": "urn:test:count",
      "$anchor": "positive",
      "type": "integer",
      "minimum": 1,
    },
    "urn:test:dialect": {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "$vocabulary": {
        "https://json-schema.org/draft/2020-12/vocab/core": true,
        "https://json-schema.org/draft/2020-12/vocab/applicator": true,
        "https://json-schema.org/draft/2020-12/vocab/unevaluated": true,
        "https://json-schema.org/draft/2020-12/vocab/validation": true,
      },
    },
  }
  let input : Json = {
    "$schema": "urn:test:dialect",
    "type": "object",
    "allOf": [
      {
        "properties": { "count": { "$ref": "count#positive" } },
        "required": ["count"],
      },
    ],
    "unevaluatedProperties": false,
  }
  let output : Json = { "$ref": "count#positive" }
  let definition = @types.ToolDefinition::new(
    "remote",
    input,
    output_schema=output,
  )
  let calls = Ref(0)
  let result = Ref((1 : Json))
  let server = MCPServer::MCPServer("test", "1").tool_definition(
    definition,
    (_, _) => {
      calls.val += 1
      Ok(@tool.Complete(@types.ToolResult::structured(result.val)))
    },
    schema_resources=resources,
    input_base_uri="https://schemas.example/input",
    output_base_uri="https://schemas.example/output",
  )
  resources["https://schemas.example/count"] = false
  assert_true(
    @validation.parse_json(
      server.handle_request(validation_call("remote", Some({ "count": 1 }))),
    )
    is { "result": _, .. },
  )
  for args in [({ "count": 0 } : Json), { "count": 1, "extra": true }] {
    assert_true(
      @validation.parse_json(
        server.handle_request(validation_call("remote", Some(args))),
      )
      is { "error": { "code": -32602, .. }, .. },
    )
  }
  assert_eq(calls.val, 1)
  result.val = 0
  assert_true(
    @validation.parse_json(
      server.handle_request(validation_call("remote", Some({ "count": 1 }))),
    )
    is { "error": { "code": -32603, .. }, .. },
  )
  assert_eq(server.registry.list_tools()[0].input_schema, input)
  for
    registry in [
      (Map([]) : Map[String, Json]),
      {
        "urn:test:dialect": {
          "$vocabulary": {
            "https://json-schema.org/draft/2020-12/vocab/core": true,
            "urn:test:unsupported": true,
          },
        },
      },
    ] {
    try
      server.tool_definition(
        definition,
        (_, _) => fail("failed replacement ran"),
        schema_resources=registry,
      )
    catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("invalid registration must fail")
    }
  }
  result.val = 2
  assert_true(
    @validation.parse_json(
      server.handle_request(validation_call("remote", Some({ "count": 2 }))),
    )
    is { "result": _, .. },
  )
}

///|
async test "tool schema resources: dynamic scope crosses remote schema resources" {
  let resources : Map[String, Json] = {
    "urn:test:tree": {
      "$dynamicAnchor": "node",
      "type": "object",
      "properties": {
        "children": { "type": "array", "items": { "$dynamicRef": "#node" } },
      },
    },
  }
  let schema : Json = {
    "$id": "urn:test:strict-tree",
    "$dynamicAnchor": "node",
    "type": "object",
    "$ref": "urn:test:tree",
    "unevaluatedProperties": false,
  }
  let server = MCPServer::MCPServer("test", "1").tool_definition(
    @types.ToolDefinition::new("tree", schema),
    (_, _) => Ok(@tool.Complete(@types.ToolResult::text("ok"))),
    schema_resources=resources,
  )
  for
    entry in [
      (({ "children": [{ "children": [] }] } : Json), true),
      ({ "children": [{ "extra": true }] }, false),
    ] {
    let (value, expected) = entry
    let reply = @validation.parse_json(
      server.handle_request(validation_call("tree", Some(value))),
    )
    assert_eq(reply is { "result": _, .. }, expected)
  }
}
