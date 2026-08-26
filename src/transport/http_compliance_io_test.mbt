///| Http_compliance I/O configuration tests — native/wasm only.
/// On js, HttpTransport is an abort stub (see unimplemented_js.mbt), so these
/// tests are gated by moon.pkg targets.

///| =====================================================

///| HTTP Transport Configuration

///|
/// =====================================================
test "compliance: HttpTransport default port is 4240" {
  let transport = HttpTransport::HttpTransport()
  @debug.assert_eq(transport.port, 4240)
}

///|
test "compliance: HttpTransport default endpoint is /mcp" {
  let transport = HttpTransport::HttpTransport()
  @debug.assert_eq(transport.endpoint_path, "/mcp")
}

///|
test "compliance: HttpTransport supports custom port and path" {
  let transport = HttpTransport::HttpTransport(
    port=8080,
    endpoint_path="/api/mcp",
  )
  @debug.assert_eq(transport.port, 8080)
  @debug.assert_eq(transport.endpoint_path, "/api/mcp")
}

///|
test "compliance: HttpTransport supports streaming" {
  let transport = HttpTransport::HttpTransport()
  assert_true(transport.supports_streaming())
}
