///|
test "tools list retains cache hints metadata extensions and pagination" {
  let result = parse_tools_list({
    "tools": [],
    "nextCursor": "next",
    "resultType": "complete",
    "ttlMs": 500,
    "cacheScope": "private",
    "_meta": {
      "io.modelcontextprotocol/serverInfo": { "name": "test", "version": "1" },
      "future": null,
    },
    "future": [1],
  })
  assert_eq(result.next_cursor, Some("next"))
  assert_eq(result.metadata.ttl_ms, Some(@types.JsonInteger::from_int(500)))
  assert_eq(result.metadata.cache_scope, Some(@types.CacheScope::Private))
  assert_eq(result.metadata.extensions.get("future"), Some(Json::array([1])))
  assert_false(result.metadata.extensions.contains("tools"))
  assert_false(result.metadata.extensions.contains("nextCursor"))
  assert_true(result.metadata.server_info() is Some(_))
}

///|
test "tool call client result uses the same public protocol owner" {
  let client_result : CallToolResult = @types.ToolResult::structured({
    "answer": 42,
  })
  assert_eq(
    client_result.to_json(),
    @types.ToolResult::structured({ "answer": 42 }).to_json(),
  )
}

///|
test "JSON-RPC client errors retain the peer code and data instead of becoming InternalError" {
  try
    parse_jsonrpc_response(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32602,\"message\":\"unknown tool\",\"data\":{\"name\":\"missing\"}}}",
    )
  catch {
    error => {
      assert_eq(error.to_error_code().as_int().unwrap(), -32602)
      assert_eq(error.message(), "unknown tool")
      assert_eq(
        error.to_error_data(),
        Some(Json::object({ "name": "missing" })),
      )
    }
  } noraise {
    _ => fail("error response must not succeed")
  }
  try
    parse_jsonrpc_response(
      "{\"result\":{},\"error\":{\"code\":-32603,\"message\":\"x\"}}",
    )
  catch {
    @types.InvalidRequest(_) => ()
    error => raise error
  } noraise {
    _ => fail("expected protocol error")
  }
}
