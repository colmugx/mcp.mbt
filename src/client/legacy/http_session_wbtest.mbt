///|
// Dependency anchor (canary): this test verifies an assumption about the
// moonbitlang/async dependency, not product code — @http.Headers lookup is
// case-insensitive. http_session.mbt relies on that property to find the
// MCP-Session-Id header regardless of the casing the client sent. If the
// dependency behavior ever changes, this test should fail before the
// product's session handling does.
//
// @http.Headers is unavailable under wasm-gc (moonbitlang/async ships no
// http surface there); keep this test on native/js/wasm.
#cfg(not(target="wasm-gc"))
test "dependency anchor: @http.Headers session-id lookup is case-insensitive" {
  let headers : @http.Headers = Map([])
  headers["content-type"] = "application/json"
  headers["MCP-SESSION-ID"] = "session-abc"
  @debug.assert_eq(headers.get("Mcp-Session-Id"), Some("session-abc"))
}
