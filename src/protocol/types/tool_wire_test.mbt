///|
test "conformance: full tool definition round trip preserves schema and metadata" {
  let wire : Json = {
    "name": "search",
    "title": "Search",
    "description": "Search offline",
    "inputSchema": {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "$defs": { "query": { "type": "string", "minLength": 1 } },
      "properties": {
        "query": { "$ref": "#/$defs/query", "x-mcp-header": "Query" },
      },
      "required": ["query"],
      "additionalProperties": false,
      "oneOf": [{ "required": ["query"] }],
    },
    "outputSchema": { "type": "array", "items": { "type": "string" } },
    "annotations": {
      "title": "Search index",
      "readOnlyHint": false,
      "destructiveHint": false,
      "idempotentHint": true,
      "openWorldHint": false,
      "com.example/hint": null,
    },
    "icons": [{ "src": "data:image/png;base64,aGk=", "theme": "dark" }],
    "_meta": { "com.example/key": [null, false] },
    "com.example/extension": {},
  }
  let tool = @types.ToolDefinition::from_json(wire)
  assert_eq(tool.to_json(), wire)
  assert_eq(
    tool.output_schema,
    Some({ "type": "array", "items": { "type": "string" } }),
  )
}

///|
test "conformance: tool optional fields preserve absence and empty values" {
  let wires : Array[Json] = [
    { "name": "empty", "inputSchema": { "type": "object" } },
    {
      "name": "empty",
      "inputSchema": { "type": "object" },
      "description": "",
      "title": "",
      "annotations": {},
      "icons": [],
      "_meta": {},
      "outputSchema": {},
    },
  ]
  for wire in wires {
    assert_eq(@types.ToolDefinition::from_json(wire).to_json(), wire)
  }
  assert_eq(@types.ToolAnnotations::new(read_only_hint=false).to_json(), {
    "readOnlyHint": false,
  })
}

///|
test "conformance: malformed known tool fields fail decoding" {
  let invalid : Array[Json] = [
    { "inputSchema": { "type": "object" } },
    { "name": "tool" },
    { "name": "tool", "inputSchema": {} },
    { "name": "tool", "inputSchema": { "type": "array" } },
    { "name": "tool", "inputSchema": { "type": "object", "$schema": null } },
    {
      "name": "tool",
      "inputSchema": { "type": "object" },
      "description": false,
    },
    {
      "name": "tool",
      "inputSchema": { "type": "object" },
      "annotations": { "readOnlyHint": "false" },
    },
    { "name": "tool", "inputSchema": { "type": "object" }, "icons": [null] },
    {
      "name": "tool",
      "inputSchema": { "type": "object" },
      "outputSchema": false,
    },
    { "name": "tool", "inputSchema": { "type": "object" }, "_meta": [] },
  ]
  for wire in invalid {
    try @types.ToolDefinition::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected malformed tool definition to fail")
    }
  }
}

///|
test "conformance: tool structured content retains every JSON kind" {
  let values : Array[Json] = [
    null,
    false,
    0,
    "",
    [],
    {},
    [null, false, { "nested": [] }],
  ]
  for value in values {
    let wire : Json = {
      "resultType": "complete",
      "content": [],
      "structuredContent": value,
      "isError": false,
      "_meta": {
        "io.modelcontextprotocol/serverInfo": { "name": "test", "version": "1" },
        "com.example/value": null,
      },
      "com.example/result": {},
    }
    let result = @types.ToolResult::from_json(wire)
    assert_eq(result.structured_content, Some(value))
    assert_eq(result.is_error, Some(false))
    assert_eq(result.to_json(), wire)
    assert_eq(
      result.metadata.server_info(),
      Some({ "name": "test", "version": "1" }),
    )
    assert_eq(
      @types.ToolResult::structured(value).structured_content,
      Some(value),
    )
  }
}

///|
test "conformance: tool results distinguish absent null and false" {
  let wires : Array[Json] = [
    { "content": [] },
    { "content": [], "structuredContent": null },
    { "content": [], "isError": false },
    { "content": [], "isError": true, "_meta": {} },
  ]
  for wire in wires {
    assert_eq(@types.ToolResult::from_json(wire).to_json(), wire)
  }
  assert_eq(
    @types.ToolResult::from_json({ "content": [] }).structured_content,
    None,
  )
  assert_eq(@types.ToolResult::from_json({ "content": [] }).is_error, None)
}

///|
test "conformance: malformed tool results and cache metadata fail decoding" {
  let invalid : Array[Json] = [
    null,
    {},
    { "content": null },
    { "content": [{ "type": "audio", "data": "aGk=" }] },
    { "content": [], "isError": null },
    { "content": [], "isError": 0 },
    { "content": [], "_meta": [] },
    { "content": [], "ttlMs": -1 },
    { "content": [], "cacheScope": "shared" },
    { "content": [], "resultType": false },
  ]
  for wire in invalid {
    try @types.ToolResult::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected malformed tool result to fail")
    }
  }
}

///|
test "conformance: cache hints retain zero private scope and extensions" {
  let wire : Json = {
    "resultType": "complete",
    "ttlMs": 0,
    "cacheScope": "private",
    "_meta": {},
    "com.example/cache": false,
  }
  let metadata = @types.ResultMetadata::from_json(wire, body_fields=[])
  assert_eq(metadata.to_json(), wire)
  assert_eq(metadata.ttl_ms, Some(0.0))
  assert_eq(metadata.cache_scope, Some(@types.CacheScope::Private))
  assert_eq(metadata.server_info(), None)
}

///|
test "conformance: tool codec isolates top level metadata and extensions" {
  let meta : Map[String, Json] = { "com.example/key": false }
  let extensions : Map[String, Json] = { "com.example/top": null }
  let tool = {
    ..@types.ToolDefinition::new("tool", { "type": "object" }, meta~),
    extensions,
  }
  let encoded = tool.to_json()
  guard encoded is Object(fields) else { fail("expected object") }
  fields.set("com.example/top", true)
  guard fields.get("_meta") is Some(Object(encoded_meta)) else {
    fail("expected metadata")
  }
  encoded_meta.set("com.example/key", true)
  assert_eq(meta.get("com.example/key"), Some(false))
  assert_eq(extensions.get("com.example/top"), Some(null))
  let result = @types.ToolResult::from_json({
    "content": [],
    "_meta": Json::object(meta),
  })
  meta.set("com.example/key", true)
  assert_eq(result.metadata.meta.unwrap().get("com.example/key"), Some(false))
}
