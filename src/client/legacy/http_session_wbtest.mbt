///|
// @http.Headers is unavailable under wasm-gc (moonbitlang/async ships no
// http surface there); keep this test on native/js/wasm.
#cfg(not(target="wasm-gc"))
test "@http.Headers session-id lookup is case-insensitive" {
  let headers : @http.Headers = Map([])
  headers["content-type"] = "application/json"
  headers["MCP-SESSION-ID"] = "session-abc"
  @debug.assert_eq(headers.get("Mcp-Session-Id"), Some("session-abc"))
}
