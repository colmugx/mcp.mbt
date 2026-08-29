///|
/// Feed an `AsyncLexbuf` from a fixed list of chunks, simulating a chunked
/// HTTP response body. Later chunks are returned on later refills; `None`
/// after the last one.
fn feed(parts : Array[String]) -> async () -> String? {
  let index = Ref(0)
  () => {
    if index.val < parts.length() {
      let chunk = parts[index.val]
      index.val += 1
      Some(chunk)
    } else {
      None
    }
  }
}

///|
async test "scan_sse_event concatenates multi-line data and records id" {
  let buf = @lexbuf.AsyncLexbuf::from_fn(
    feed(["id: evt-1\n", "data: {\"a\":", "\ndata: 1}\n", "event: progress\n\n"]),
  )
  let (payload, id) = scan_sse_event(buf, [], None)
  @debug.assert_eq(id, Some("evt-1"))
  @debug.assert_eq(payload, Some("{\"a\":\n1}"))
}

///|
async test "scan_sse_event returns None payload for heartbeat comments" {
  let buf = @lexbuf.AsyncLexbuf::from_fn(
    feed([": keep-alive\n", "id: evt-2\n\n"]),
  )
  let (payload, id) = scan_sse_event(buf, [], None)
  @debug.assert_eq(id, Some("evt-2"))
  @debug.assert_eq(payload, None)
}

///|
async test "scan_sse_event survives patterns spanning refill chunks" {
  let buf = @lexbuf.AsyncLexbuf::from_fn(
    feed(["da", "ta: pa", "rtial\n", "\rid: next\r", "\r\n\r\n"]),
  )
  let (payload, _id) = scan_sse_event(buf, [], None)
  @debug.assert_eq(payload, Some("partial"))
}

///|
async test "scan_sse_event accepts CRLF and CR terminators" {
  let buf = @lexbuf.AsyncLexbuf::from_fn(
    feed(["data: crlf\r\n", "data: lone-cr\r", "data: lf\n", "\r\n"]),
  )
  let (payload, _id) = scan_sse_event(buf, [], None)
  @debug.assert_eq(payload, Some("crlf\nlone-cr\nlf"))
}

///|
async test "scan_sse_event strips at most one space after the field colon" {
  let buf = @lexbuf.AsyncLexbuf::from_fn(
    feed(["data:nospace\n", "data:  twospaces\n\n"]),
  )
  let (payload, _id) = scan_sse_event(buf, [], None)
  @debug.assert_eq(payload, Some("nospace\n twospaces"))
}

///|
async test "scan_sse_event dispatches unterminated final line at EOF" {
  let buf = @lexbuf.AsyncLexbuf::from_fn(feed(["data: tail-without-newline"]))
  let (payload, _id) = scan_sse_event(buf, [], None)
  @debug.assert_eq(payload, Some("tail-without-newline"))
}

///|
async test "scan_sse_event at EOF with no data returns None" {
  let buf = @lexbuf.AsyncLexbuf::from_fn(feed([]))
  let (payload, id) = scan_sse_event(buf, [], None)
  @debug.assert_eq(payload, None)
  @debug.assert_eq(id, None)
}

///|
async test "scan_sse_event ignores unknown fields and keeps scanning" {
  let buf = @lexbuf.AsyncLexbuf::from_fn(
    feed(["retry: 5000\n", "event: progress\n", "data: x\n\n"]),
  )
  let (payload, _id) = scan_sse_event(buf, [], None)
  @debug.assert_eq(payload, Some("x"))
}

///|
async test "read_sse_event events flow one per call until EOF" {
  let buf = @lexbuf.AsyncLexbuf::from_fn(
    feed(["data: one\n\n", "data: two\n\n"]),
  )
  let (first, _) = scan_sse_event(buf, [], None)
  let (second, _) = scan_sse_event(buf, [], None)
  let (third, _) = scan_sse_event(buf, [], None)
  @debug.assert_eq(first, Some("one"))
  @debug.assert_eq(second, Some("two"))
  @debug.assert_eq(third, None)
}

///|
/// `@qc.check` predicates are synchronous, so the async scanner is driven
/// over pre-generated samples instead. Payloads containing line terminators
/// are excluded: they legitimately frame as multiple SSE lines.
async test "prop: scan_sse_event recovers formatted payloads" {
  let payloads : Array[String] = @qc.samples(200).filter(s => {
    !s.contains("\n") && !s.contains("\r")
  })
  for s in payloads {
    let buf = @lexbuf.AsyncLexbuf::from_fn(feed(["data: " + s + "\n\n"]))
    let (payload, _) = scan_sse_event(buf, [], None)
    if payload != Some(s) {
      fail("scan_sse_event failed to roundtrip payload: \{s}")
    }
  }
}

///|
test "sse_event_verdict: opening keepalive with empty data is skipped" {
  // nowledge-mem opens every SSE stream with `data:` (empty) + `id:` +
  // `retry:` before the first real payload.
  @debug.assert_eq(sse_event_verdict(Some(""), Some("0")), Skip)
  @debug.assert_eq(sse_event_verdict(Some("  "), None), Skip)
}

///|
test "sse_event_verdict: real payloads pass through verbatim" {
  @debug.assert_eq(
    sse_event_verdict(Some("{\"jsonrpc\":\"2.0\"}"), None),
    Message("{\"jsonrpc\":\"2.0\"}"),
  )
}

///|
test "sse_event_verdict: heartbeat with id is skipped, bare EOF ends" {
  // A dispatched comment-only heartbeat carries the id but no data lines —
  // that is not end-of-stream.
  @debug.assert_eq(sse_event_verdict(None, Some("evt-2")), Skip)
  // (None, None) is the scan's EOF shape.
  @debug.assert_eq(sse_event_verdict(None, None), Eof)
}
