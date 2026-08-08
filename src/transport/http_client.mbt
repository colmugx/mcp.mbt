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
  }
}

///|
/// Parse one SSE event from a streaming HTTP client body.
/// Returns (json_payload, event_id) — `event_id` is kept for forward-compat
/// but unused (the 2026-07-28 transport drops `Last-Event-ID` resumability).
async fn read_sse_event(
  client : @http.Client,
) -> (String?, String?) raise @types.TransportError {
  let data_lines : Array[String] = []
  let mut event_id : String? = None
  while true {
    let line = client.read_until("\n") catch {
      e => raise @types.ReadError("SSE read error: \{e}")
    }
    match line {
      None => return (None, None)
      Some(l) =>
        if l == "" {
          break
        } else if l.has_prefix("data: ") {
          data_lines.push(l)
        } else if l.has_prefix("id: ") {
          event_id = Some(l[4:].trim().to_owned())
        }
      // Ignore other SSE fields (event:, retry:, comment lines starting with ':')
    }
  }
  if data_lines.is_empty() {
    (None, event_id)
  } else {
    let mut result = ""
    let mut first = true
    for dl in data_lines {
      if !first {
        result = result + "\n"
      }
      first = false
      let json = dl[6:].to_owned() // strip "data: " prefix
      result = result + json
    }
    (Some(result), event_id)
  }
}

///|
/// POST a JSON-RPC request to the server. Sets the required request-metadata
/// headers (`MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`) and accepts
/// either a single JSON object or an SSE stream as the response. All response
/// messages are pushed onto `pending_responses` for `receive` to drain.
pub async fn HttpClientTransport::send(
  self : HttpClientTransport,
  message : String,
) -> Unit raise @types.TransportError {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }
  let body_bytes = @utf8.encode(message)
  let headers : Map[String, String] = Default::default()
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
    Some(n) => headers["Mcp-Name"] = n
    None => ()
  }
  match self.auth_token {
    Some(t) => headers["Authorization"] = "Bearer " + t
    None => ()
  }
  let client = @http.post_stream(self.base_url, headers~) catch {
    e => raise @types.WriteError("HTTP POST failed: \{e}")
  }
  client.write(body_bytes) catch {
    e => {
      client.close()
      raise @types.WriteError("Failed to write body: \{e}")
    }
  }
  client.flush() catch {
    e => {
      client.close()
      raise @types.WriteError("Failed to flush: \{e}")
    }
  }
  let response = client.end_request() catch {
    e => {
      client.close()
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
    client.close()
    let msg = match www_auth {
      "" => "HTTP 401 Unauthorized"
      _ => "HTTP 401 Unauthorized — WWW-Authenticate: " + www_auth
    }
    raise @types.Unauthorized(msg)
  }
  if response.code == 403 {
    client.close()
    raise @types.Forbidden("HTTP 403 Forbidden — insufficient permissions")
  }
  if response.code >= 400 {
    client.close()
    raise @types.WriteError(
      "HTTP " + response.code.to_string() + " " + response.reason,
    )
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
    client.close()
  } else {
    // Single JSON response: read the entire body and queue it.
    let body = client.read_all() catch {
      e => {
        client.close()
        raise @types.ReadError("Failed to read response body: \{e}")
      }
    }
    client.close()
    let body_str = body.text() catch {
      e => raise @types.ReadError("Failed to read response body: \{e}")
    }
    self.pending_responses.put(body_str) catch {
      _ => ()
    }
  }
}

///|
/// Drain the next response message (single JSON or one SSE event) queued by
/// `send`. Returns None when the queue is empty.
pub async fn HttpClientTransport::receive(
  self : HttpClientTransport,
) -> String? raise @types.TransportError {
  if self.closed {
    return None
  }
  let next = self.pending_responses.try_get() catch { _ => None }
  match next {
    Some(s) => Some(s)
    None => None
  }
}

///|
/// Send a JSON-RPC notification (no id, fire-and-forget). Per spec §B, a
/// notification POST is answered with `202 Accepted` and no body.
pub async fn HttpClientTransport::send_notification(
  self : HttpClientTransport,
  notification : @types.Notification,
) -> Unit raise @types.TransportError {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }
  let json_body = notification.to_jsonrpc_string()
  let body_bytes = @utf8.encode(json_body)
  let headers : Map[String, String] = Default::default()
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
    e => raise @types.WriteError("Failed to send notification: \{e}")
  }
  // Fire-and-forget: write body, end request, close.
  try {
    client.write(body_bytes)
    client.flush()
    let _ = client.end_request()
  } catch {
    _ => ()
  }
  client.close()
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
    let method = match obj.get("method") {
      Some(String(m)) => m
      _ => return None
    }
    if method != "tools/call" &&
      method != "resources/read" &&
      method != "prompts/get" {
      return None
    }
    let params = match obj.get("params") {
      Some(Object(p)) => p
      _ => return None
    }
    let key = if method == "resources/read" { "uri" } else { "name" }
    match params.get(key) {
      Some(String(s)) => Some(s)
      _ => None
    }
  } else {
    None
  }
}
