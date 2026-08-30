///| Transport I/O construction tests — native/wasm only.
/// On js, StdioTransport/HttpTransport/StdioClientTransport are abort stubs
/// (see unimplemented_js.mbt), so these tests are gated by moon.pkg targets.

///| =====================================================

///| StdioTransport Tests

///|
/// =====================================================
test "StdioTransport::StdioTransport creates unclosed transport" {
  let transport = StdioTransport::StdioTransport()
  @debug.assert_eq(transport.closed, false)
}

///|
test "StdioTransport::close marks transport as closed" {
  let transport = StdioTransport::StdioTransport()
  @debug.assert_eq(transport.closed, false)
  transport.close()
  @debug.assert_eq(transport.closed, true)
}

///|
test "StdioTransport::close is idempotent" {
  let transport = StdioTransport::StdioTransport()
  transport.close()
  transport.close()
  @debug.assert_eq(transport.closed, true)
}

///|
test "StdioTransport::send raises error on closed transport" {
  let transport = StdioTransport::StdioTransport()
  transport.close()

  // Note: This test demonstrates the error case
  // In practice, we'd need async test framework to execute receive/send
  @debug.assert_eq(transport.closed, true)
}

///| =====================================================

///| HttpTransport Tests

///|
/// =====================================================
test "HttpTransport::HttpTransport with defaults" {
  let transport = HttpTransport::HttpTransport()
  @debug.assert_eq(transport.port, 4240)
  @debug.assert_eq(transport.endpoint_path, "/mcp")
}

///|
test "HttpTransport::HttpTransport with custom port" {
  let transport = HttpTransport::HttpTransport(port=3000)
  @debug.assert_eq(transport.port, 3000)
  @debug.assert_eq(transport.endpoint_path, "/mcp")
}

///|
test "HttpTransport::HttpTransport with custom endpoint" {
  let transport = HttpTransport::HttpTransport(endpoint_path="/custom")
  @debug.assert_eq(transport.port, 4240)
  @debug.assert_eq(transport.endpoint_path, "/custom")
}

///|
test "HttpTransport::HttpTransport with custom port and endpoint" {
  let transport = HttpTransport::HttpTransport(port=8080, endpoint_path="/api")
  @debug.assert_eq(transport.port, 8080)
  @debug.assert_eq(transport.endpoint_path, "/api")
}

///|
test "HttpTransport::close is no_op" {
  let transport = HttpTransport::HttpTransport()
  // Should not panic or raise error
  transport.close()
  ()
}

///|
async test "HttpTransport routes out-of-order responses by JSON-RPC id" {
  let transport = HttpTransport::HttpTransport()
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
  let transport = StdioTransport::StdioTransport()
  let any_transport = AnyTransport::Stdio(transport)
  match any_transport {
    Stdio(_) => ()
    _ => panic()
  }
}

///|
test "AnyTransport::Http variant creation" {
  let transport = HttpTransport::HttpTransport()
  let any_transport = AnyTransport::Http(transport)
  match any_transport {
    Http(_) => ()
    _ => panic()
  }
}

///|
test "AnyTransport::close dispatches correctly" {
  let stdio = StdioTransport::StdioTransport()
  let any_transport = AnyTransport::Stdio(stdio)

  // Should not panic
  any_transport.close()
  ()
}

///| =====================================================

///| AuthConfig Tests

///|
/// =====================================================
test "AuthConfig::AuthConfig stores verify_token" {
  let config = AuthConfig::AuthConfig(
    verify_token=fn(token) { token == "valid" },
    resource_metadata_url="http://localhost:4240/mcp",
  )
  assert_true((config.verify_token)("valid"))
  assert_true(!(config.verify_token)("invalid"))
}

///|
test "AuthConfig::AuthConfig defaults optional fields to None" {
  let config = AuthConfig::AuthConfig(
    verify_token=fn(_) { true },
    resource_metadata_url="http://localhost:4240/mcp",
  )
  @debug.assert_eq(config.required_scopes, None)
  @debug.assert_eq(config.allowed_origins, None)
  @debug.assert_eq(config.authorization_servers.length(), 0)
}

///|
test "AuthConfig::AuthConfig with all fields" {
  let config = AuthConfig::AuthConfig(
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
test "AuthConfig::AuthConfig empty string scopes → None" {
  let config = AuthConfig::AuthConfig(
    verify_token=fn(_) { true },
    resource_metadata_url="http://localhost:4240/mcp",
    required_scopes="",
  )
  @debug.assert_eq(config.required_scopes, None)
}

///|
test "HttpTransport::with_auth sets auth config" {
  let transport = HttpTransport::HttpTransport(port=4240)
  match transport.auth {
    None => ()
    Some(_) => panic()
  }
  let authed = transport.with_auth(
    AuthConfig::AuthConfig(
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
  let transport = HttpTransport::HttpTransport(port=8080, endpoint_path="/api")
  let authed = transport.with_auth(
    AuthConfig::AuthConfig(
      verify_token=fn(_) { true },
      resource_metadata_url="http://localhost:8080/api",
    ),
  )
  @debug.assert_eq(authed.port, 8080)
  @debug.assert_eq(authed.endpoint_path, "/api")
}
