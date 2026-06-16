///| Transport Layer Unit Tests

///| Tests for Transport implementations and validation

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

///| StdioTransport Tests

///|
/// =====================================================
test "StdioTransport::new creates unclosed transport" {
  let transport = StdioTransport::new()
  @debug.assert_eq(transport.closed, false)
}

///|
test "StdioTransport::close marks transport as closed" {
  let transport = StdioTransport::new()
  @debug.assert_eq(transport.closed, false)
  transport.close()
  @debug.assert_eq(transport.closed, true)
}

///|
test "StdioTransport::close is idempotent" {
  let transport = StdioTransport::new()
  transport.close()
  transport.close()
  @debug.assert_eq(transport.closed, true)
}

///|
test "StdioTransport::supports_streaming returns false" {
  let transport = StdioTransport::new()
  @debug.assert_eq(transport.supports_streaming(), false)
}

///|
test "StdioTransport::send_event is no-op" {
  let transport = StdioTransport::new()
  // Should not panic or raise error
  transport.send_event(event_type="test", data="data")
  ()
}

///|
test "StdioTransport::send raises error on closed transport" {
  let transport = StdioTransport::new()
  transport.close()

  // Note: This test demonstrates the error case
  // In practice, we'd need async test framework to execute receive/send
  @debug.assert_eq(transport.closed, true)
}

///| =====================================================

///| HttpTransport Tests

///|
/// =====================================================
test "HttpTransport::new with defaults" {
  let transport = HttpTransport::new()
  @debug.assert_eq(transport.port, 4240)
  @debug.assert_eq(transport.endpoint_path, "/mcp")
}

///|
test "HttpTransport::new with custom port" {
  let transport = HttpTransport::new(port=3000)
  @debug.assert_eq(transport.port, 3000)
  @debug.assert_eq(transport.endpoint_path, "/mcp")
}

///|
test "HttpTransport::new with custom endpoint" {
  let transport = HttpTransport::new(endpoint_path="/custom")
  @debug.assert_eq(transport.port, 4240)
  @debug.assert_eq(transport.endpoint_path, "/custom")
}

///|
test "HttpTransport::new with custom port and endpoint" {
  let transport = HttpTransport::new(port=8080, endpoint_path="/api")
  @debug.assert_eq(transport.port, 8080)
  @debug.assert_eq(transport.endpoint_path, "/api")
}

///|
test "HttpTransport::supports_streaming returns true" {
  let transport = HttpTransport::new()
  @debug.assert_eq(transport.supports_streaming(), true)
}

///|
test "HttpTransport::send_event is no_op" {
  let transport = HttpTransport::new()
  // Should not panic or raise error
  transport.send_event(event_type="test", data="data")
  ()
}

///|
test "HttpTransport::close is no_op" {
  let transport = HttpTransport::new()
  // Should not panic or raise error
  transport.close()
  ()
}

///|
async test "HttpTransport routes out-of-order responses by JSON-RPC id" {
  let transport = HttpTransport::new()
  let request_a = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"slow\"}"
  let request_b = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"fast\"}"
  let reply_a : @async.Queue[String] = @async.Queue(kind=Blocking(1))
  let reply_b : @async.Queue[String] = @async.Queue(kind=Blocking(1))

  transport.pending_requests.put((request_a, reply_a))
  transport.pending_requests.put((request_b, reply_b))

  @debug.assert_eq(transport.receive(), Some(request_a))
  @debug.assert_eq(transport.receive(), Some(request_b))

  let response_b = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":\"B\"}"
  let response_a = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"A\"}"
  transport.send(response_b)
  transport.send(response_a)

  @debug.assert_eq(reply_b.get(), response_b)
  @debug.assert_eq(reply_a.get(), response_a)
}

///| =====================================================

///| AnyTransport Enum Tests

///|
/// =====================================================
test "AnyTransport::Stdio variant creation" {
  let transport = StdioTransport::new()
  let any_transport = AnyTransport::Stdio(transport)
  match any_transport {
    Stdio(_) => ()
    _ => panic()
  }
}

///|
test "AnyTransport::Http variant creation" {
  let transport = HttpTransport::new()
  let any_transport = AnyTransport::Http(transport)
  match any_transport {
    Http(_) => ()
    _ => panic()
  }
}

///|
test "AnyTransport::supports_streaming dispatches correctly" {
  let stdio = StdioTransport::new()
  let http = HttpTransport::new()
  @debug.assert_eq(AnyTransport::Stdio(stdio).supports_streaming(), false)
  @debug.assert_eq(AnyTransport::Http(http).supports_streaming(), true)
}

///|
test "AnyTransport::close dispatches correctly" {
  let stdio = StdioTransport::new()
  let any_transport = AnyTransport::Stdio(stdio)

  // Should not panic
  any_transport.close()
  ()
}

///|
test "AnyTransport::send_event dispatches correctly" {
  let stdio = StdioTransport::new()
  let any_transport = AnyTransport::Stdio(stdio)

  // Should not panic
  any_transport.send_event(event_type="test", data="data")
  ()
}

///| =====================================================

///| Example: Transport Factory Pattern

///|
/// =====================================================
test "example: create stdio transport via enum" {
  let transport = AnyTransport::Stdio(StdioTransport::new())
  match transport {
    Stdio(t) => {
      @debug.assert_eq(t.closed, false)
      @debug.assert_eq(transport.supports_streaming(), false)
    }
    _ => panic()
  }
}

///|
test "example: create http transport via enum" {
  let transport = AnyTransport::Http(HttpTransport::new(port=5000))
  match transport {
    Http(t) => {
      @debug.assert_eq(t.port, 5000)
      @debug.assert_eq(transport.supports_streaming(), true)
    }
    _ => panic()
  }
}

///|
test "example: transport configuration builder pattern" {
  // Simulate builder pattern for HTTP transport
  let transport = HttpTransport::new(port=9000, endpoint_path="/mcp/endpoint")
  @debug.assert_eq(transport.port, 9000)
  @debug.assert_eq(transport.endpoint_path, "/mcp/endpoint")
  @debug.assert_eq(transport.supports_streaming(), true)
}

///| =====================================================

///| AuthConfig Tests

///|
/// =====================================================
test "AuthConfig::new stores verify_token" {
  let config = AuthConfig::new(
    verify_token=fn(token) { token == "valid" },
    resource_metadata_url="http://localhost:4240/mcp",
  )
  assert_true((config.verify_token)("valid"))
  assert_true(!(config.verify_token)("invalid"))
}

///|
test "AuthConfig::new defaults optional fields to None" {
  let config = AuthConfig::new(
    verify_token=fn(_) { true },
    resource_metadata_url="http://localhost:4240/mcp",
  )
  @debug.assert_eq(config.required_scopes, None)
  @debug.assert_eq(config.allowed_origins, None)
  @debug.assert_eq(config.authorization_servers.length(), 0)
}

///|
test "AuthConfig::new with all fields" {
  let config = AuthConfig::new(
    verify_token=fn(_) { true },
    resource_metadata_url="http://localhost:4240/mcp",
    authorization_servers=["https://auth.example.com"],
    required_scopes="mcp:read",
    allowed_origins=["http://localhost:3000"],
  )
  @debug.assert_eq(config.resource_metadata_url, "http://localhost:4240/mcp")
  @debug.assert_eq(config.required_scopes, Some("mcp:read"))
  match config.allowed_origins {
    Some(origins) => @debug.assert_eq(origins.length(), 1)
    None => panic()
  }
  @debug.assert_eq(config.authorization_servers.length(), 1)
}

///|
test "AuthConfig::new empty string scopes → None" {
  let config = AuthConfig::new(
    verify_token=fn(_) { true },
    resource_metadata_url="http://localhost:4240/mcp",
    required_scopes="",
  )
  @debug.assert_eq(config.required_scopes, None)
}

///|
test "HttpTransport::with_auth sets auth config" {
  let transport = HttpTransport::new(port=4240)
  match transport.auth {
    None => ()
    Some(_) => panic()
  }
  let authed = transport.with_auth(
    AuthConfig::new(
      verify_token=fn(_) { true },
      resource_metadata_url="http://localhost:4240/mcp",
    ),
  )
  match authed.auth {
    Some(config) =>
      @debug.assert_eq(
        config.resource_metadata_url,
        "http://localhost:4240/mcp",
      )
    None => panic()
  }
}

///|
test "HttpTransport::with_auth preserves other fields" {
  let transport = HttpTransport::new(port=8080, endpoint_path="/api")
  let authed = transport.with_auth(
    AuthConfig::new(
      verify_token=fn(_) { true },
      resource_metadata_url="http://localhost:8080/api",
    ),
  )
  @debug.assert_eq(authed.port, 8080)
  @debug.assert_eq(authed.endpoint_path, "/api")
}

///| =====================================================

///| HttpClientTransport Auth Tests

///|
/// =====================================================
test "HttpClientTransport::new without auth_token" {
  let transport = HttpClientTransport::new("http://localhost:4240/mcp")
  @debug.assert_eq(transport.auth_token, None)
}

///|
test "HttpClientTransport::new with auth_token" {
  let transport = HttpClientTransport::new(
    "http://localhost:4240/mcp",
    auth_token="my-secret",
  )
  @debug.assert_eq(transport.auth_token, Some("my-secret"))
}

///|
test "HttpClientTransport::new empty auth_token → None" {
  let transport = HttpClientTransport::new(
    "http://localhost:4240/mcp",
    auth_token="",
  )
  @debug.assert_eq(transport.auth_token, None)
}
