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
/// Extract the JSON-RPC `id` member from a serialized request body, for
/// echoing in transport-level error responses. Returns `None` when the body
/// is not a JSON object or carries no `id` — JSON-RPC allows omitting `id`
/// when it cannot be determined from the (possibly malformed) request.
pub fn request_id_from_body(body : String) -> Json? {
  let json = @json.parse(body) catch { _ => return None }
  if json is Object(obj) {
    obj.get("id")
  } else {
    None
  }
}

///|
/// Serialize a JSON-RPC 2.0 error response body for a transport-level
/// rejection, echoing the request `id` extracted from `body` when readable.
fn jsonrpc_error_body(error : @types.MCPError, body~ : String) -> String {
  let error_obj : Map[String, Json] = Default::default()
  error_obj.set("code", Json::number(error.to_error_code().to_double()))
  error_obj.set("message", Json::string(error.message()))
  match error.to_error_data() {
    Some(data) => error_obj.set("data", data)
    None => ()
  }
  let response : Map[String, Json] = Default::default()
  response.set("jsonrpc", Json::string("2.0"))
  response.set("error", Json::object(error_obj))
  match request_id_from_body(body) {
    Some(id) => response.set("id", id)
    None => ()
  }
  Json::object(response).stringify()
}

///|
/// Build a `HeaderMismatch` (-32020) JSON-RPC error response body. The
/// request `id` is echoed when readable from `body`.
pub fn header_mismatch_error(detail : String, body~ : String) -> String {
  jsonrpc_error_body(@types.HeaderMismatch(detail), body~)
}

///|
/// Build an `Invalid params` (-32602) JSON-RPC error response body for a
/// malformed request rejected at transport entry (e.g. a request whose
/// `params._meta` is missing required fields). The request `id` is echoed
/// when readable from `body`.
pub fn invalid_params_error(detail : String, body~ : String) -> String {
  jsonrpc_error_body(@types.InvalidParams(detail), body~)
}

///|
/// Build an `UnsupportedProtocolVersion` (-32022) JSON-RPC error response
/// body. The request `id` is echoed when readable from `body`; the error is
/// transport-level, so unreadable ids are simply omitted.
pub fn unsupported_protocol_version_error(
  requested : String,
  body~ : String,
) -> String {
  jsonrpc_error_body(
    @types.UnsupportedProtocolVersion(
      "Unsupported protocol version",
      supported=[@types.ProtocolVersion],
      requested~,
    ),
    body~,
  )
}
