///|
test "parse_initialize_response extracts server info" {
  try
    parse_initialize_response(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"serverInfo\":{\"name\":\"test-server\",\"version\":\"1.2.3\"},\"protocolVersion\":\"2025-11-25\"}}",
    )
  catch {
    _ => fail("expected Ok")
  } noraise {
    info => {
      @debug.assert_eq(info.name, "test-server")
      @debug.assert_eq(info.version, "1.2.3")
    }
  }
}

///|
test "parse_initialize_response errors when result missing" {
  try
    parse_initialize_response(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32603,\"message\":\"boom\"}}",
    )
  catch {
    e => @debug.assert_eq(e.message(), "initialize response missing result")
  } noraise {
    _ => fail("expected Err")
  }
}

///|
test "build_ping_request has correct shape" {
  let json = @json.parse(build_ping_request(42))
  match json {
    Object(obj) => {
      @debug.assert_eq(obj.get("jsonrpc"), Some(Json::string("2.0")))
      @debug.assert_eq(obj.get("method"), Some(Json::string("ping")))
      match obj.get("id") {
        Some(Number(n, ..)) => @debug.assert_eq(n, 42.0)
        _ => fail("expected id number")
      }
    }
    _ => fail("expected object")
  }
}
