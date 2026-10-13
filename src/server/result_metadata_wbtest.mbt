///|
test "server preserves explicit handler cache hints instead of replacing them with defaults" {
  let server = MCPServer::MCPServer("test", "1")
  let result : Json = {
    "contents": [],
    "ttlMs": 0,
    "cacheScope": "private",
    "_meta": { "trace": "handler" },
    "future": false,
  }
  let response = parse_result(
    jsonrpc_cacheable_success_str(
      server,
      @types.RequestId::Int(1),
      result,
      30000,
      "public",
    ),
  )
  assert_eq(json_get(response, "ttlMs"), Json::number(0))
  assert_eq(json_get(response, "cacheScope"), Json::string("private"))
  assert_eq(json_get(response, "future"), Json::boolean(false))
  assert_eq(
    json_get(json_get(response, "_meta"), "trace"),
    Json::string("handler"),
  )
  assert_false(json_has(result, "resultType"))
  assert_false(
    json_has(json_get(result, "_meta"), "io.modelcontextprotocol/serverInfo"),
  )
}

///|
test "server cache defaults fill absent hints independently" {
  let server = MCPServer::MCPServer("test", "1")
  let response = parse_result(
    jsonrpc_cacheable_success_str(
      server,
      @types.RequestId::Int(1),
      { "contents": [], "ttlMs": 0 },
      30000,
      "private",
    ),
  )
  assert_eq(json_get(response, "ttlMs"), Json::number(0))
  assert_eq(json_get(response, "cacheScope"), Json::string("private"))
}

///|
test "server rejects invalid public metadata numeric fields before serializing a success" {
  let server = MCPServer::MCPServer("test", "1")
  // Typed records cannot even hold a fractional ttl; the wire-level invalid
  // spellings (negative, fractional, non-finite) are rejected pre-serialization.
  let result = @types.ToolResult::text("done")
  let result = {
    ..result,
    metadata: {
      ..result.metadata,
      ttl_ms: Some(@types.JsonInteger::from_int(-1)),
    },
  }
  for
    response in [
      jsonrpc_success_str(server, @types.RequestId::Int(1), result.to_json()),
      jsonrpc_cacheable_success_str(
        server,
        @types.RequestId::Int(1),
        result.to_json(),
        30000,
        "private",
      ),
    ] {
    let response = @json.parse(response)
    assert_eq(
      json_get(json_get(response, "error"), "code"),
      Json::number(-32603),
    )
    assert_false(json_has(response, "result"))
  }
  for ttl_ms in ["1.5", "-1", "0.30000000000000000000001", "9007199254740992.5"] {
    // The preserving parser keeps every literal, so boundary spellings reach
    // the typed decoder instead of being rounded away by the core parser.
    let wire = @validation.parse_json(
      "{\"content\":[],\"ttlMs\":" + ttl_ms + "}",
    )
    for
      response in [
        jsonrpc_success_str(server, @types.RequestId::Int(1), wire),
        jsonrpc_cacheable_success_str(
          server,
          @types.RequestId::Int(1),
          wire,
          30000,
          "private",
        ),
      ] {
      let response = @json.parse(response)
      assert_eq(
        json_get(json_get(response, "error"), "code"),
        Json::number(-32603),
      )
      assert_false(json_has(response, "result"))
    }
  }
}

///|
test "server complete branch owns resultType without mutating handler metadata" {
  let server = MCPServer::MCPServer("test", "1")
  let result : Json = {
    "content": [],
    "resultType": "input_required",
    "_meta": {},
  }
  let response = parse_result(
    jsonrpc_success_str(server, @types.RequestId::Int(1), result),
  )
  assert_eq(json_get(response, "resultType"), Json::string("complete"))
  assert_eq(json_get(result, "resultType"), Json::string("input_required"))
}

///|
async test "server validates complete handler wire shapes before publication" {
  let server = MCPServer::MCPServer("test", "1")
    .tool("invalid", "test", { "type": "object" }, (_context, _args) => {
      Ok(
        @types.ToolResult::success([
          @types.ContentBlock::Unknown(Json::object({ "type": "text" })),
        ]),
      )
    })
    .resource("memo://invalid", "invalid", "test", "text/plain", _context => {
      let result = @types.ResourceReadResult::text("done", uri="memo://invalid")
      Ok({
        ..result,
        metadata: {
          ..result.metadata,
          ttl_ms: Some(@types.JsonInteger::from_int(-1)),
        },
      })
    })
    .prompt("invalid", "test", [], (_context, _args) => {
      Ok(
        @types.GetPromptResult::new([
          {
            role: "system",
            content: @types.ContentBlock::text("x"),
            extensions: Map([]),
          },
        ]),
      )
    })
  for
    (method_name, params) in [
      ("tools/call", Json::object({ "name": "invalid" })),
      ("resources/read", Json::object({ "uri": "memo://invalid" })),
      ("prompts/get", Json::object({ "name": "invalid" })),
    ] {
    guard params is Object(fields) else { fail("test params must be objects") }
    fields.set("_meta", valid_request_meta())
    let response = @json.parse(
      server.handle_request(
        Json::object({
          "jsonrpc": "2.0",
          "id": 1,
          "method": method_name,
          "params": params,
        }).stringify(),
      ),
    )
    assert_eq(
      json_get(json_get(response, "error"), "code"),
      Json::number(-32603),
    )
    assert_false(json_has(response, "result"))
  }
}

///|
async test "resource handler cache hints survive the complete runtime path" {
  let server = MCPServer::MCPServer("test", "1").resource(
    "memo://cache",
    "cache",
    "test",
    "text/plain",
    _context => {
      let result = @types.ResourceReadResult::text("done", uri="memo://cache")
      Ok({
        ..result,
        metadata: {
          ..result.metadata,
          ttl_ms: Some(@types.JsonInteger::from_int(0)),
          cache_scope: Some(@types.CacheScope::Public),
        },
      })
    },
  )
  let request = Json::object({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "resources/read",
    "params": { "uri": "memo://cache", "_meta": valid_request_meta() },
  }).stringify()
  let result = parse_result(server.handle_request(request))
  assert_eq(json_get(result, "ttlMs"), Json::number(0))
  assert_eq(json_get(result, "cacheScope"), Json::string("public"))
}
