///|
/// HttpClientTransport — MCP client connecting to a remote HTTP server.
///
/// Implements the stateless 2026-07-28 Streamable HTTP transport: every
/// JSON-RPC request is its own POST, carrying the required request-metadata
/// headers (`MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`). A POST may be
/// answered with either a single JSON object or an SSE stream scoped to that
/// request; both are collected into `pending_responses` and surfaced one at a
/// time by `receive`.
///
/// The legacy session model (`Mcp-Session-Id`, GET long-poll SSE,
/// `Last-Event-ID` resumability, DELETE close) is removed. Server→client
/// notifications now flow on per-request SSE response streams (progress) or
/// `subscriptions/listen` (change events), not a standalone GET channel.
pub struct HttpClientTransport {
  base_url : String
  auth_token : String?
  mut closed : Bool
  pending_responses : @async.Queue[String]
  /// `x-mcp-header` mirror schemas learned from `tools/list`, keyed by tool
  /// name. Each entry is (property path from the arguments root, header name
  /// suffix): on `tools/call`, the value at that path is mirrored into the
  /// `Mcp-Param-{suffix}` request header per spec §B (SEP-2243).
  tool_header_schemas : Map[String, Array[(Array[String], String)]]
}

///|
/// Install the `x-mcp-header` mirror schema set (called by the client layer
/// after validating `tools/list` tool definitions). Emission itself is done
/// by `send` when building `tools/call` request headers.
pub fn HttpClientTransport::set_tool_header_schemas(
  self : HttpClientTransport,
  schemas : Map[String, Array[(Array[String], String)]],
) -> Unit {
  schemas.each(fn(k, v) { self.tool_header_schemas.set(k, v) })
}

///|
pub fn HttpClientTransport::HttpClientTransport(
  base_url : String,
  auth_token? : String = "",
) -> HttpClientTransport {
  {
    base_url,
    auth_token: if auth_token == "" {
      None
    } else {
      Some(auth_token)
    },
    closed: false,
    pending_responses: @async.Queue(kind=Unbounded),
    tool_header_schemas: {},
  }
}

///|
/// POST a JSON-RPC request to the server. Sets the required request-metadata
/// headers (`MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`) and accepts
/// either a single JSON object or an SSE stream as the response. All response
/// messages are pushed onto `pending_responses` for `receive` to drain.
/// Cancellation note: every error-translating catch below re-raises when
/// `@async.is_being_cancelled()` — otherwise a `with_timeout` cancellation
/// injected at a suspension point would be re-labeled as WriteError/ReadError,
/// losing its identity to the enclosing task group's timeout fallback.
pub async fn HttpClientTransport::send(
  self : HttpClientTransport,
  message : String,
) -> Unit {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }
  let body_bytes = @utf8.encode(message)
  let headers : @http.Headers = Default::default()
  headers["Content-Type"] = "application/json"
  headers["Accept"] = "application/json, text/event-stream"
  headers["Content-Length"] = body_bytes.length().to_string()
  headers["MCP-Protocol-Version"] = @types.ProtocolVersion
  // Mirror body fields into headers for intermediary routing (spec §B).
  // Mcp-Method is required for all requests; Mcp-Name for the three
  // name-bearing methods.
  match extract_field(message, "method") {
    Some(m) => headers["Mcp-Method"] = m
    None => ()
  }
  match extract_name_field(message) {
    Some(n) => headers["Mcp-Name"] = encode_header_value(n)
    None => ()
  }
  // Emit Mcp-Param-* headers for tools/call when the client layer has
  // provided x-mcp-header schemas from tools/list.
  match extract_field(message, "method") {
    Some("tools/call") =>
      match extract_name_field(message) {
        Some(tool_name) =>
          match self.tool_header_schemas.get(tool_name) {
            Some(schemas) =>
              for entry in schemas {
                let (path, suffix) = entry
                match extract_argument_value(message, path) {
                  Some(value) =>
                    headers["Mcp-Param-" + suffix] = encode_header_value(value)
                  None => ()
                }
              }
            None => ()
          }
        None => ()
      }
    _ => ()
  }
  match self.auth_token {
    Some(t) => headers["Authorization"] = "Bearer " + t
    None => ()
  }
  let client = @http.post_stream(self.base_url, headers~) catch {
    e =>
      if @async.is_being_cancelled() {
        raise e
      } else {
        raise @types.WriteError("HTTP POST failed: \{e}")
      }
  }
  // `send` consumes the client on every path, so a plain `defer` covers both
  // the success exits and every raise (including async cancellation) below.
  defer client.close()
  client.write(body_bytes) catch {
    e =>
      if @async.is_being_cancelled() {
        raise e
      } else {
        raise @types.WriteError("Failed to write body: \{e}")
      }
  }
  client.flush() catch {
    e =>
      if @async.is_being_cancelled() {
        raise e
      } else {
        raise @types.WriteError("Failed to flush: \{e}")
      }
  }
  let response = client.end_request() catch {
    e =>
      if @async.is_being_cancelled() {
        raise e
      } else {
        raise @types.ReadError("Failed to get response: \{e}")
      }
  }
  // Stateless transport: 404 no longer means "session expired". Surface it
  // (and other 4xx/5xx) as a transport error for the caller to handle.
  if response.code == 401 {
    let www_auth = match response.headers.get("www-authenticate") {
      Some(v) => v
      None => ""
    }
    let msg = match www_auth {
      "" => "HTTP 401 Unauthorized"
      _ => "HTTP 401 Unauthorized — WWW-Authenticate: " + www_auth
    }
    raise @types.Unauthorized(msg)
  }
  if response.code == 403 {
    raise @types.Forbidden("HTTP 403 Forbidden — insufficient permissions")
  }
  if response.code >= 400 {
    // Read the response body so era probes can inspect modern JSON-RPC errors
    // (UnsupportedProtocolVersion / HeaderMismatch / MissingRequiredClientCapability).
    let body_str = try {
      let body = client.read_all()
      body.text()
    } catch {
      _ => ""
    }
    raise @types.HttpError(response.code, body_str)
  }
  // Determine response mode from Content-Type
  let content_type = match response.headers.get("content-type") {
    Some(ct) => ct.to_lower()
    None => "application/json"
  }
  if content_type.contains("text/event-stream") {
    // SSE response: read events from the streaming body until the stream ends.
    // Each event is a JSON-RPC message (progress notifications followed by
    // the final response). All are queued for `receive`.
    while true {
      let (data_opt, _id_opt) = read_sse_event(client)
      match data_opt {
        Some(event_json) =>
          self.pending_responses.put(event_json) catch {
            _ => ()
          }
        None => break
      }
    }
  } else {
    // Single JSON response: read the entire body and queue it.
    let body = client.read_all() catch {
      e =>
        if @async.is_being_cancelled() {
          raise e
        } else {
          raise @types.ReadError("Failed to read response body: \{e}")
        }
    }
    let body_str = body.text() catch {
      e =>
        if @async.is_being_cancelled() {
          raise e
        } else {
          raise @types.ReadError("Failed to read response body: \{e}")
        }
    }
    self.pending_responses.put(body_str) catch {
      _ => ()
    }
  }
}

///|
/// Drain the next response message (single JSON or one SSE event) queued by
/// `send`. Blocks asynchronously until a message is available. Returns `None`
/// when the transport is closed or the underlying queue is closed/empty.
pub async fn HttpClientTransport::receive(
  self : HttpClientTransport,
) -> String? noraise {
  if self.closed {
    return None
  }
  let result : String? = Some(self.pending_responses.get()) catch { _ => None }
  result
}

///|
/// Send a JSON-RPC notification (no id, fire-and-forget). Per spec §B, a
/// notification POST is answered with `202 Accepted` and no body.
pub async fn HttpClientTransport::send_notification(
  self : HttpClientTransport,
  notification : @types.Notification,
) -> Unit {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }
  let json_body = notification.to_jsonrpc_string()
  let body_bytes = @utf8.encode(json_body)
  let headers : @http.Headers = Default::default()
  headers["Content-Type"] = "application/json"
  headers["Content-Length"] = body_bytes.length().to_string()
  headers["MCP-Protocol-Version"] = @types.ProtocolVersion
  match extract_field(json_body, "method") {
    Some(m) => headers["Mcp-Method"] = m
    None => ()
  }
  match self.auth_token {
    Some(t) => headers["Authorization"] = "Bearer " + t
    None => ()
  }
  let client = @http.post_stream(self.base_url, headers~) catch {
    e =>
      if @async.is_being_cancelled() {
        raise e
      } else {
        raise @types.WriteError("Failed to send notification: \{e}")
      }
  }
  defer client.close()
  // Fire-and-forget: write body, end request; errors are intentionally swallowed.
  try {
    client.write(body_bytes)
    client.flush()
    let _ = client.end_request()
  } catch {
    _ => ()
  }
}

///|
/// Client transport does not push events to server.
pub fn HttpClientTransport::send_event(
  _self : HttpClientTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  ignore(event_type)
  ignore(data)
}

///|
pub fn HttpClientTransport::supports_streaming(
  _self : HttpClientTransport,
) -> Bool {
  true
}

///|
pub fn HttpClientTransport::close(self : HttpClientTransport) -> Unit {
  self.closed = true
}

///|
/// Extract a top-level string field from a JSON-RPC message body.
/// Used to mirror `method` (and `params.name`/`params.uri` below) into the
/// `Mcp-Method` / `Mcp-Name` request headers.
fn extract_field(body : String, field : String) -> String? {
  let json = @json.parse(body) catch { _ => return None }
  if json is Object(obj) {
    match obj.get(field) {
      Some(String(s)) => Some(s)
      _ => None
    }
  } else {
    None
  }
}

///|
/// Extract the `Mcp-Name` source value from a request body:
/// `params.name` for tools/call|prompts/get, `params.uri` for resources/read.
/// Returns None for methods that do not require `Mcp-Name`.
fn extract_name_field(body : String) -> String? {
  let json = @json.parse(body) catch { _ => return None }
  if json is Object(obj) {
    let met = match obj.get("method") {
      Some(String(m)) => m
      _ => return None
    }
    if met != "tools/call" && met != "resources/read" && met != "prompts/get" {
      return None
    }
    let params = match obj.get("params") {
      Some(Object(p)) => p
      _ => return None
    }
    let key = if met == "resources/read" { "uri" } else { "name" }
    match params.get(key) {
      Some(String(s)) => Some(s)
      _ => None
    }
  } else {
    None
  }
}

///|
/// Extract the value at a property path inside `params.arguments` for
/// `tools/call` requests. Returns `None` when the path is absent or the final
/// value is `null`. Converts string, safe integer, and boolean values to their
/// header string representations.
pub fn extract_argument_value(body : String, path : Array[String]) -> String? {
  let json = @json.parse(body) catch { _ => return None }
  if json is Object(obj) {
    match obj.get("params") {
      Some(Object(params)) =>
        match params.get("arguments") {
          Some(Object(args)) => get_json_path_value(args, path)
          _ => None
        }
      _ => None
    }
  } else {
    None
  }
}

///|
/// Walk a chain of `properties` keys through a JSON object and convert the
/// final primitive value to its header string form.
fn get_json_path_value(
  args : Map[String, Json],
  path : Array[String],
) -> String? {
  let mut current : Json? = Some(Json::object(args))
  for key in path {
    current = match current {
      Some(Object(obj)) => obj.get(key)
      _ => None
    }
  }
  match current {
    Some(String(s)) => Some(s)
    Some(Number(n, ..)) =>
      if is_safe_integer(n) {
        Some(n.to_int64().to_string())
      } else {
        // Non-integer or out-of-JS-safe-range numbers are not emitted as
        // headers; the caller treats this as "no value present".
        None
      }
    Some(True) => Some("true")
    Some(False) => Some("false")
    Some(Null) | None => None
    _ => None
  }
}

///|
/// Returns `true` when `n` is an integer within the JavaScript safe integer
/// range (`-(2^53-1)` to `2^53-1`).
fn is_safe_integer(n : Double) -> Bool {
  let i = n.to_int64()
  let min : Int64 = -9007199254740991L
  let max : Int64 = 9007199254740991L
  n == i.to_double() && i >= min && i <= max
}
