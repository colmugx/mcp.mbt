///|
/// SSE (Server-Sent Events) scanner for streamable HTTP transports.
///
/// `read_sse_event` consumes exactly one event — or detects EOF — from a
/// streaming HTTP response body. Tokenization runs through `lexscan` over an
/// `@lexbuf.AsyncLexbuf`, so the per-line matching stays on the
/// compiler-optimized regex path and patterns may span refill-chunk
/// boundaries.
///
/// Semantics follow the WHATWG SSE spec: lines end with `\n`, `\r\n`, or
/// `\r`; a blank line dispatches the accumulated event; `data:`/`id:` values
/// strip a single leading space; comments and unknown fields are ignored;
/// consecutive `data:` lines join with `\n`; an unterminated final line at
/// EOF is dispatched as if the terminator were present.
pub async fn read_sse_event(
  client : @http.Client,
) -> (String?, String?) raise @types.TransportError {
  // Malformed UTF-8 cannot be raised through `AsyncLexbuf`'s fixed generic
  // refill signature, so the closure flags the failure and reports EOF to
  // stop the scan; the error is raised here, after scanning unwinds.
  let decode_failed = Ref(false)
  let buf = @lexbuf.AsyncLexbuf::from_fn(() => {
    let chunk = client.read_some(max_len=8192)
    match chunk {
      Some(bytes) =>
        Some(@utf8.decode(bytes)) catch {
          _ => {
            decode_failed.val = true
            None
          }
        }
      None => None
    }
  })
  let scanned = scan_sse_event(buf, [], None) catch { _ => (None, None) }
  if decode_failed.val {
    raise @types.ReadError("SSE body is not valid UTF-8")
  }
  scanned
}

///|
/// What a response-stream consumer should do with one scanned SSE event.
pub enum SseEventVerdict {
  /// A JSON-RPC payload to queue for `receive`.
  Message(String)
  /// A keepalive/heartbeat event (dispatched but carrying no payload) —
  /// keep scanning, the stream is still open.
  Skip
  /// End of stream.
  Eof
} derive(Eq, @debug.Debug)

///|
/// Classify one `read_sse_event` result for a response stream.
///
/// Servers may open or interleave keepalive events: an event dispatched with
/// an empty or whitespace-only `data:` payload (nowledge-mem opens every
/// stream with `data:` + `id:` + `retry:`), or a comment-only heartbeat that
/// carries an `id` but no data lines. None of those are JSON-RPC messages —
/// queueing an empty payload desyncs response matching (initialize would
/// parse the empty string), and treating a heartbeat as EOF ends the scan
/// before the real reply arrives. A heartbeat with neither data nor id is
/// indistinguishable from EOF by the scan result and still ends the stream.
pub fn sse_event_verdict(data : String?, id : String?) -> SseEventVerdict {
  match data {
    Some(event_json) =>
      if event_json.trim().length() > 0 {
        Message(event_json)
      } else {
        Skip
      }
    None => if id is Some(_) { Skip } else { Eof }
  }
}

///|
/// Scan one event from `buf`, accumulating `data` lines and the last `id`
/// seen. The recursion is the loop: one arm per SSE line kind, one
/// terminating arm for the blank dispatch line, and the catch-all for EOF.
async fn scan_sse_event(
  buf : @lexbuf.AsyncLexbuf,
  data : Array[StringView],
  event_id : String?,
) -> (String?, String?) {
  lexscan buf {
    re"^data:[^\n\r]*(\r\n|\r|\n)?" as line => {
      data.push(sse_field_value(line, field="data:"))
      scan_sse_event(buf, data, event_id)
    }
    re"^id:[^\n\r]*(\r\n|\r|\n)?" as line =>
      scan_sse_event(
        buf,
        data,
        Some(sse_field_value(line, field="id:").to_owned()),
      )
    // Blank line: dispatch what has accumulated. Comment-only events
    // (heartbeats) carry the id but no payload.
    re"^(\r\n|\r|\n)" => (join_sse_data(data), event_id)
    // Comment line.
    re"^:[^\n\r]*(\r\n|\r|\n)?" => scan_sse_event(buf, data, event_id)
    // Unknown field line.
    re"^[^\n\r]+(\r\n|\r|\n)?" => scan_sse_event(buf, data, event_id)
    // EOF: flush a partially accumulated event, per spec.
    _ => (join_sse_data(data), event_id)
  }
}

///|
/// Reduce a matched `data:`/`id:` line to its field value: drop the field
/// name, at most one leading space, and the trailing line terminator.
fn sse_field_value(matched : StringView, field~ : String) -> StringView {
  let body = drop_sse_eol(matched[field.length():])
  if body is [' ', .. rest] {
    rest
  } else {
    body
  }
}

///|
/// Drop the trailing `\r\n`, `\n`, or `\r` from a fully matched line, if any.
fn drop_sse_eol(line : StringView) -> StringView {
  if line.has_suffix("\r\n") {
    line[:line.length() - 2]
  } else if line.has_suffix("\n") || line.has_suffix("\r") {
    line[:line.length() - 1]
  } else {
    line
  }
}

///|
/// Join accumulated `data` values with `\n`; an event without `data` lines
/// has no payload.
fn join_sse_data(data : Array[StringView]) -> String? {
  if data.is_empty() {
    None
  } else {
    Some(data.join("\n"))
  }
}
