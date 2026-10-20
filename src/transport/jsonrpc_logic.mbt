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
  let json = @validation.parse_json(message) catch { _ => return Other }
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
pub fn jsonrpc_error_code(message : String) -> Int32? {
  let json = @validation.parse_json(message) catch { _ => return None }
  if json is Object(obj) {
    match obj.get("error") {
      Some(Object(err)) =>
        match err.get("code") {
          Some(value) =>
            @types.JsonInteger::from_json(value).as_int() catch {
              _ => None
            }
          _ => None
        }
      _ => None
    }
  } else {
    None
  }
}

///|
fn check_http_response(
  message : String,
  expected : Json?,
) -> JsonRpcKind raise @types.TransportError {
  let value = @validation.parse_json(message) catch {
    _ => raise @types.ReadError("Invalid JSON in HTTP response")
  }
  guard value is Object(fields) &&
    fields.get("jsonrpc") == Some(Json::string("2.0")) else {
    raise @types.ReadError("HTTP response must be a JSON-RPC 2.0 message")
  }
  if fields.get("method") is Some(String(_)) &&
    !fields.contains("id") &&
    !fields.contains("result") &&
    !fields.contains("error") {
    return Notification
  }
  guard !fields.contains("method") &&
    fields.contains("result") != fields.contains("error") &&
    fields.get("id") is Some(id) &&
    expected is Some(expected) else {
    raise @types.ReadError(
      "HTTP response stream cannot contain independent requests or malformed responses",
    )
  }
  let matches = (@types.RequestId::from_json(id) ==
  @types.RequestId::from_json(expected)) catch {
    _ => false
  }
  if !matches {
    raise @types.ReadError(
      "HTTP response id does not match its originating request",
    )
  }
  FinalResponse
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
  let json = @validation.parse_json(body) catch { _ => return None }
  if json is Object(obj) {
    match obj.get("id") {
      Some(value) =>
        Some(@types.RequestId::from_json(value).to_json()) catch {
          _ => None
        }
      None => None
    }
  } else {
    None
  }
}

///|
/// Serialize a JSON-RPC 2.0 error response body for a transport-level
/// rejection, echoing the request `id` extracted from `body` when readable.
fn jsonrpc_error_body(error : @types.MCPError, body~ : String) -> String {
  let response : Map[String, Json] = Default::default()
  response.set("jsonrpc", Json::string("2.0"))
  response.set("error", error.to_jsonrpc_error())
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

///|
/// Explicit trait method promotion for current MoonBit toolchains.
pub extend JsonRpcKind with Eq::{not_equal, equal}

///|
pub extend JsonRpcKind with @moonbitlang/core/debug.Debug::{to_repr}
