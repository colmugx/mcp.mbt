// MCPServer auth-builder tests. Gated to native+wasm: AuthConfig aborts on
// js / wasm-gc (support matrix — server is native+wasm only).

///|
#cfg(any(target="native", target="wasm"))
test "MCPServer::with_auth sets auth_config" {
  let server = MCPServer::MCPServer("auth-server", "1.0.0")
  match server.auth_config {
    None => ()
    Some(_) => panic()
  }
  let authed = server.with_auth(
    @transport.AuthConfig::AuthConfig(
      verify_token=fn(token) { token == "valid" },
      resource_metadata_url="http://localhost:4240/mcp",
    ),
  )
  match authed.auth_config {
    Some(config) =>
      @debug.assert_eq(
        config.resource_metadata_url,
        "http://localhost:4240/mcp",
      )
    None => panic()
  }
}

///|
#cfg(any(target="native", target="wasm"))
test "MCPServer::with_auth preserves other fields" {
  let server = MCPServer::MCPServer("test", "1.0.0")
    .with_title("My Server")
    .with_description("A test server")
    .with_auth(
      @transport.AuthConfig::AuthConfig(
        verify_token=fn(_) { true },
        resource_metadata_url="http://localhost:4240/mcp",
      ),
    )
  @debug.assert_eq(server.name, "test")
  @debug.assert_eq(server.version, "1.0.0")
  @debug.assert_eq(server.title, Some("My Server"))
  @debug.assert_eq(server.description, Some("A test server"))
  match server.auth_config {
    Some(_) => ()
    None => panic()
  }
}
