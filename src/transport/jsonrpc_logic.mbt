///| Pure-logic JSON-RPC / SSE framing helpers shared by all targets.
/// Split from http_server.mbt so js (and wasm-gc) keep these APIs even
/// though the transport I/O itself is gated.

///|
/// Classification of JSON-RPC messages arriving on the server-side reply
/// queue. Used to decide whether a POST response is a single JSON object or
/// an SSE stream.
pub(all) enum JsonRpcKind {
  Notification
  FinalResponse
  Other
} derive(Eq, Debug)

///|
/// Returns `true` when the JSON body is a JSON-RPC notification
/// (`method` present, `id` absent).
pub fn is_notification(body : Json) -> Bool {
  if body is Object(obj) {
    obj.get("method") is Some(_) && obj.get("id") is None
  } else {
    false
  }
}

///|
/// Classify a serialized JSON-RPC message for response-mode selection.
pub fn classify_jsonrpc_message(message : String) -> JsonRpcKind {
  let json = @json.parse(message) catch { _ => return Other }
  if json is Object(obj) {
    let has_method = obj.get("method") is Some(_)
    let has_id = obj.get("id") is Some(_)
    let has_result = obj.get("result") is Some(_)
    let has_error = obj.get("error") is Some(_)
    if has_method && !has_id {
      Notification
    } else if has_id && (has_result || has_error) {
      FinalResponse
    } else {
      Other
    }
  } else {
    Other
  }
}

///|
/// Extract the JSON-RPC error code from a serialized response, if any.
pub fn jsonrpc_error_code(message : String) -> Int? {
  let json = @json.parse(message) catch { _ => return None }
  if json is Object(obj) {
    match obj.get("error") {
      Some(Object(err)) =>
        match err.get("code") {
          Some(Number(n, ..)) => Some(n.to_int())
          _ => None
        }
      _ => None
    }
  } else {
    None
  }
}

///|
/// Format a JSON-RPC payload as one SSE event line.
pub fn sse_event_line(json : String) -> String {
  "data: " + json + "\n\n"
}

///|
/// Build an `UnsupportedProtocolVersion` (-32022) JSON-RPC error response
/// body. The response has no `id` because the failure is transport-level.
pub fn unsupported_protocol_version_error(requested : String) -> String {
  let err = @types.UnsupportedProtocolVersion(
    "Unsupported protocol version",
    supported=[@types.ProtocolVersion],
    requested~,
  )
  let data = match err.to_error_data() {
    Some(d) => d
    None => null
  }
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "error": Json::object({
      "code": Json::number(err.to_error_code().to_double()),
      "message": Json::string(err.message()),
      "data": data,
    }),
  }).stringify()
}
