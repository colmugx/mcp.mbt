///| Transport Layer Unit Tests

///| Tests for Transport implementations and validation
/// (I/O transport construction tests live in transport_io_test.mbt, which is
/// gated to native/wasm — on js those transports are abort stubs.)

///|
/// JSON-RPC Validation Tests
test "validate_jsonrpc_message accepts valid request" {
  let message = "{\"jsonrpc\":\"2.0\",\"method\":\"test\",\"id\":1}"
  match validate_jsonrpc_message(message) {
    Ok(_) => ()
    Err(_) => panic()
  }
}

///|
test "validate_jsonrpc_message accepts valid response" {
  let message = "{\"jsonrpc\":\"2.0\",\"result\":\"success\",\"id\":1}"
  match validate_jsonrpc_message(message) {
    Ok(_) => ()
    Err(_) => panic()
  }
}

///|
test "validate_jsonrpc_message accepts valid error response" {
  let message = "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"},\"id\":1}"
  match validate_jsonrpc_message(message) {
    Ok(_) => ()
    Err(_) => panic()
  }
}

///|
test "validate_jsonrpc_message rejects missing jsonrpc field" {
  let message = "{\"method\":\"test\",\"id\":1}"
  match validate_jsonrpc_message(message) {
    Ok(_) => panic()
    Err(e) => assert_true(e.message().contains("jsonrpc"))
  }
}

///|
test "validate_jsonrpc_message rejects invalid jsonrpc version" {
  let message = "{\"jsonrpc\":\"1.0\",\"method\":\"test\",\"id\":1}"
  match validate_jsonrpc_message(message) {
    Ok(_) => panic()
    Err(_) => ()
  }
}

///|
test "validate_jsonrpc_message rejects non-object JSON" {
  let message = "\"just a string\""
  match validate_jsonrpc_message(message) {
    Ok(_) => panic()
    Err(_) => ()
  }
}

///|
test "validate_jsonrpc_message rejects invalid JSON" {
  let message = "{invalid json}"
  match validate_jsonrpc_message(message) {
    Ok(_) => panic()
    Err(_) => ()
  }
}

///|
test "validate_jsonrpc_message rejects message without method/result/error" {
  let message = "{\"jsonrpc\":\"2.0\",\"id\":1}"
  match validate_jsonrpc_message(message) {
    Ok(_) => panic()
    Err(e) =>
      assert_true(
        e.message().contains("method") ||
        e.message().contains("result") ||
        e.message().contains("error"),
      )
  }
}

///| =====================================================

///| HttpClientTransport Auth Tests

///|
/// =====================================================
test "HttpClientTransport::HttpClientTransport without auth_token" {
  let transport = HttpClientTransport::HttpClientTransport(
    "http://localhost:4240/mcp",
  )
  @debug.assert_eq(transport.auth_token, None)
}

///|
test "HttpClientTransport::HttpClientTransport with auth_token" {
  let transport = HttpClientTransport::HttpClientTransport(
    "http://localhost:4240/mcp",
    auth_token="my-secret",
  )
  @debug.assert_eq(transport.auth_token, Some("my-secret"))
}

///|
test "HttpClientTransport::HttpClientTransport empty auth_token → None" {
  let transport = HttpClientTransport::HttpClientTransport(
    "http://localhost:4240/mcp",
    auth_token="",
  )
  @debug.assert_eq(transport.auth_token, None)
}
