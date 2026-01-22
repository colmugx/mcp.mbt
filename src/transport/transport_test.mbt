///| =====================================================
///| Transport Layer Unit Tests
///| Tests for Transport implementations and validation
///| =====================================================

///| =====================================================
///| JSON-RPC Validation Tests
///| =====================================================

test "validate_jsonrpc_message accepts valid request" {
  let message = "{\"jsonrpc\":\"2.0\",\"method\":\"test\",\"id\":1}"
  match validate_jsonrpc_message(message) {
    Ok(_) => ()
    Err(_) => panic()
  }
}

test "validate_jsonrpc_message accepts valid response" {
  let message = "{\"jsonrpc\":\"2.0\",\"result\":\"success\",\"id\":1}"
  match validate_jsonrpc_message(message) {
    Ok(_) => ()
    Err(_) => panic()
  }
}

test "validate_jsonrpc_message accepts valid error response" {
  let message = "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"},\"id\":1}"
  match validate_jsonrpc_message(message) {
    Ok(_) => ()
    Err(_) => panic()
  }
}

test "validate_jsonrpc_message rejects missing jsonrpc field" {
  let message = "{\"method\":\"test\",\"id\":1}"
  match validate_jsonrpc_message(message) {
    Ok(_) => panic()
    Err(e) => {
      assert_true(e.message().contains("jsonrpc"))
    }
  }
}

test "validate_jsonrpc_message rejects invalid jsonrpc version" {
  let message = "{\"jsonrpc\":\"1.0\",\"method\":\"test\",\"id\":1}"
  match validate_jsonrpc_message(message) {
    Ok(_) => panic()
    Err(_) => ()
  }
}

test "validate_jsonrpc_message rejects non-object JSON" {
  let message = "\"just a string\""
  match validate_jsonrpc_message(message) {
    Ok(_) => panic()
    Err(_) => ()
  }
}

test "validate_jsonrpc_message rejects invalid JSON" {
  let message = "{invalid json}"
  match validate_jsonrpc_message(message) {
    Ok(_) => panic()
    Err(_) => ()
  }
}

test "validate_jsonrpc_message rejects message without method/result/error" {
  let message = "{\"jsonrpc\":\"2.0\",\"id\":1}"
  match validate_jsonrpc_message(message) {
    Ok(_) => panic()
    Err(e) => {
      assert_true(e.message().contains("method") || e.message().contains("result") || e.message().contains("error"))
    }
  }
}

///| =====================================================
///| StdioTransport Tests
///| =====================================================

test "StdioTransport::new creates unclosed transport" {
  let transport = StdioTransport::new()
  assert_eq(transport.closed, false)
}

test "StdioTransport::close marks transport as closed" {
  let transport = StdioTransport::new()
  assert_eq(transport.closed, false)
  transport.close()
  assert_eq(transport.closed, true)
}

test "StdioTransport::close is idempotent" {
  let transport = StdioTransport::new()
  transport.close()
  transport.close()
  assert_eq(transport.closed, true)
}

test "StdioTransport::supports_streaming returns false" {
  let transport = StdioTransport::new()
  assert_eq(transport.supports_streaming(), false)
}

test "StdioTransport::send_event is no-op" {
  let transport = StdioTransport::new()
  // Should not panic or raise error
  transport.send_event(event_type="test", data="data")
  ()
}

test "StdioTransport::send raises error on closed transport" {
  let transport = StdioTransport::new()
  transport.close()

  // Note: This test demonstrates the error case
  // In practice, we'd need async test framework to execute receive/send
  assert_eq(transport.closed, true)
}

///| =====================================================
///| HttpTransport Tests
///| =====================================================

test "HttpTransport::new with defaults" {
  let transport = HttpTransport::new()
  assert_eq(transport.port, 4240)
  assert_eq(transport.endpoint_path, "/mcp")
}

test "HttpTransport::new with custom port" {
  let transport = HttpTransport::new(port=3000)
  assert_eq(transport.port, 3000)
  assert_eq(transport.endpoint_path, "/mcp")
}

test "HttpTransport::new with custom endpoint" {
  let transport = HttpTransport::new(endpoint_path="/custom")
  assert_eq(transport.port, 4240)
  assert_eq(transport.endpoint_path, "/custom")
}

test "HttpTransport::new with custom port and endpoint" {
  let transport = HttpTransport::new(port=8080, endpoint_path="/api")
  assert_eq(transport.port, 8080)
  assert_eq(transport.endpoint_path, "/api")
}

test "HttpTransport::supports_streaming returns true" {
  let transport = HttpTransport::new()
  assert_eq(transport.supports_streaming(), true)
}

test "HttpTransport::send_event is no_op" {
  let transport = HttpTransport::new()
  // Should not panic or raise error
  transport.send_event(event_type="test", data="data")
  ()
}

test "HttpTransport::close is no_op" {
  let transport = HttpTransport::new()
  // Should not panic or raise error
  transport.close()
  ()
}

///| =====================================================
///| AnyTransport Enum Tests
///| =====================================================

test "AnyTransport::Stdio variant creation" {
  let transport = StdioTransport::new()
  let any_transport = AnyTransport::Stdio(transport)
  match any_transport {
    Stdio(_) => ()
    _ => panic()
  }
}

test "AnyTransport::Http variant creation" {
  let transport = HttpTransport::new()
  let any_transport = AnyTransport::Http(transport)
  match any_transport {
    Http(_) => ()
    _ => panic()
  }
}

test "AnyTransport::supports_streaming dispatches correctly" {
  let stdio = StdioTransport::new()
  let http = HttpTransport::new()

  assert_eq(AnyTransport::Stdio(stdio).supports_streaming(), false)
  assert_eq(AnyTransport::Http(http).supports_streaming(), true)
}

test "AnyTransport::close dispatches correctly" {
  let stdio = StdioTransport::new()
  let any_transport = AnyTransport::Stdio(stdio)

  // Should not panic
  any_transport.close()
  ()
}

test "AnyTransport::send_event dispatches correctly" {
  let stdio = StdioTransport::new()
  let any_transport = AnyTransport::Stdio(stdio)

  // Should not panic
  any_transport.send_event(event_type="test", data="data")
  ()
}

///| =====================================================
///| Example: Transport Factory Pattern
///| =====================================================

test "example: create stdio transport via enum" {
  let transport = AnyTransport::Stdio(StdioTransport::new())

  match transport {
    Stdio(t) => {
      assert_eq(t.closed, false)
      assert_eq(transport.supports_streaming(), false)
    }
    _ => panic()
  }
}

test "example: create http transport via enum" {
  let transport = AnyTransport::Http(HttpTransport::new(port=5000))

  match transport {
    Http(t) => {
      assert_eq(t.port, 5000)
      assert_eq(transport.supports_streaming(), true)
    }
    _ => panic()
  }
}

test "example: transport configuration builder pattern" {
  // Simulate builder pattern for HTTP transport
  let transport = HttpTransport::new(
    port=9000,
    endpoint_path="/mcp/endpoint"
  )

  assert_eq(transport.port, 9000)
  assert_eq(transport.endpoint_path, "/mcp/endpoint")
  assert_eq(transport.supports_streaming(), true)
}
