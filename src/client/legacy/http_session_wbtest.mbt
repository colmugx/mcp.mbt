///|
test "@http.Headers session-id lookup is case-insensitive" {
  let headers : @http.Headers = Map([])
  headers["content-type"] = "application/json"
  headers["MCP-SESSION-ID"] = "session-abc"
  @debug.assert_eq(headers.get("Mcp-Session-Id"), Some("session-abc"))
}
