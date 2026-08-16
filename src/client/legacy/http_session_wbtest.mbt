///|
test "parse_sse_event concatenates multi-line data and records id" {
  let (payload, id) = parse_sse_event([
    "id: evt-1", "data: {\"a\":", "data: 1}", "event: progress",
  ])
  @debug.assert_eq(id, Some("evt-1"))
  @debug.assert_eq(payload, Some("{\"a\":\n1}"))
}

///|
test "parse_sse_event returns None payload for heartbeat" {
  let (payload, id) = parse_sse_event(["id: evt-2", "event: heartbeat"])
  @debug.assert_eq(id, Some("evt-2"))
  @debug.assert_eq(payload, None)
}

///|
test "extract_session_id is case-insensitive" {
  let headers : Map[String, String] = Map([])
  headers["content-type"] = "application/json"
  headers["MCP-SESSION-ID"] = "session-abc"
  @debug.assert_eq(extract_session_id(headers), Some("session-abc"))
}
