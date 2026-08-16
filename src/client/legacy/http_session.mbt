///|
/// 2025-11-25 Streamable HTTP session-aware client transport.
///
/// This transport is intentionally separate from the modern `@transport.AnyTransport`
/// enum: it holds a `Mcp-Session-Id` returned during `initialize` and re-sends it on
/// every subsequent POST. It also terminates the session with an HTTP DELETE in
/// `close`. The legacy GET long-poll SSE channel and `Last-Event-ID` resumability
/// are not implemented.
pub struct LegacyHttpSessionTransport {
  base_url : String
  auth_token : String?
  mut session_id : String?
  mut closed : Bool
  pending_responses : @async.Queue[String]
}

///|
pub fn LegacyHttpSessionTransport::LegacyHttpSessionTransport(
  url~ : String,
  auth_token? : String = "",
) -> LegacyHttpSessionTransport {
  {
    base_url: url,
    auth_token: if auth_token == "" {
      None
    } else {
      Some(auth_token)
    },
    session_id: None,
    closed: false,
    pending_responses: @async.Queue(kind=Unbounded),
  }
}

///|
/// Look up a header by case-insensitive name.
fn get_header_ci(headers : Map[String, String], name : String) -> String? {
  let target = name.to_lower()
  for k, v in headers {
    if k.to_lower() == target {
      return Some(v)
    }
  }
  None
}

///|
/// Extract the legacy session id from response headers.
fn extract_session_id(headers : Map[String, String]) -> String? {
  get_header_ci(headers, "Mcp-Session-Id")
}

///|
/// Fill in the common request headers for legacy Streamable HTTP.
fn LegacyHttpSessionTransport::apply_request_headers(
  self : LegacyHttpSessionTransport,
  headers : Map[String, String],
) -> Unit {
  headers["Content-Type"] = "application/json"
  headers["Accept"] = "application/json, text/event-stream"
  headers["MCP-Protocol-Version"] = legacy_protocol_version
  match self.auth_token {
    Some(t) => headers["Authorization"] = "Bearer " + t
    None => ()
  }
  match self.session_id {
    Some(s) => headers["Mcp-Session-Id"] = s
    None => ()
  }
}

///|
/// Perform the HTTP POST, handle status codes, capture the session id, and return
/// the connected client positioned at the response body.
async fn LegacyHttpSessionTransport::do_post(
  self : LegacyHttpSessionTransport,
  message : String,
) -> (@http.Response, @http.Client) raise @types.TransportError {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }
  let body_bytes = @utf8.encode(message)
  let headers : Map[String, String] = Map([])
  self.apply_request_headers(headers)
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
  match extract_session_id(response.headers) {
    Some(s) => self.session_id = Some(s)
    None => ()
  }
  (response, client)
}

///|
/// Parse the lines of a single SSE event into its JSON-RPC payload.
/// The event id is returned for forward-compatibility but is intentionally unused
/// (this SDK does not implement `Last-Event-ID` resumability).
fn parse_sse_event(lines : Array[String]) -> (String?, String?) {
  let data_lines : Array[String] = []
  let mut event_id : String? = None
  for l in lines {
    if l.has_prefix("data: ") {
      data_lines.push(l)
    } else if l.has_prefix("id: ") {
      event_id = Some(l[4:].trim().to_owned())
    }
  }
  if data_lines.is_empty() {
    return (None, event_id)
  }
  let mut result = ""
  let mut first = true
  for dl in data_lines {
    if !first {
      result = result + "\n"
    }
    first = false
    result = result + dl[6:].to_owned()
  }
  (Some(result), event_id)
}

///|
/// Read one SSE event from the streaming response body.
async fn read_sse_event(
  client : @http.Client,
) -> (String?, String?) raise @types.TransportError {
  let lines : Array[String] = []
  while true {
    let line = client.read_until("\n") catch {
      e => raise @types.ReadError("SSE read error: \{e}")
    }
    match line {
      None => return parse_sse_event(lines)
      Some(l) => {
        let l = l.trim_end().to_owned()
        if l == "" {
          break
        }
        lines.push(l)
      }
    }
  }
  parse_sse_event(lines)
}

///|
/// POST a JSON-RPC request to the legacy MCP endpoint. If the server returns an
/// `Mcp-Session-Id` header, it is stored for all later requests. Responses may be
/// a single JSON object or an SSE stream; every JSON-RPC payload is queued for
/// `receive`.
pub async fn LegacyHttpSessionTransport::send(
  self : LegacyHttpSessionTransport,
  message : String,
) -> Unit raise @types.TransportError {
  let (response, client) = self.do_post(message)
  let content_type = match response.headers.get("content-type") {
    Some(ct) => ct.to_lower()
    None => "application/json"
  }
  if content_type.contains("text/event-stream") {
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
    let body = client.read_all() catch {
      e => {
        client.close()
        raise @types.ReadError("Failed to read response body: \{e}")
      }
    }
    client.close()
    let body_str = body.text() catch {
      e => raise @types.ReadError("Failed to decode response body: \{e}")
    }
    self.pending_responses.put(body_str) catch {
      _ => ()
    }
  }
}

///|
/// Drain the next response message queued by `send`. Returns `None` when the
/// queue is empty.
pub fn LegacyHttpSessionTransport::receive(
  self : LegacyHttpSessionTransport,
) -> String? {
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
/// Send a JSON-RPC notification (no id, fire-and-forget). Per the 2025-11-25
/// spec the server answers with HTTP 202 Accepted and no body.
pub async fn LegacyHttpSessionTransport::send_notification(
  self : LegacyHttpSessionTransport,
  notification : @types.Notification,
) -> Unit raise @types.TransportError {
  let json_body = notification.to_jsonrpc_string()
  let (_, client) = self.do_post(json_body)
  client.close()
}

///|
/// Best-effort session termination. If a session id is held, sends an HTTP DELETE
/// to the MCP endpoint with the `Mcp-Session-Id` header. Errors are ignored.
pub async fn LegacyHttpSessionTransport::close(
  self : LegacyHttpSessionTransport,
) -> Unit {
  if self.closed {
    return
  }
  match self.session_id {
    Some(sid) => {
      let headers : Map[String, String] = Map([])
      headers["Mcp-Session-Id"] = sid
      match self.auth_token {
        Some(t) => headers["Authorization"] = "Bearer " + t
        None => ()
      }
      try {
        let _ = @http.request(self.base_url, @http.Delete, headers, b"")
      } catch {
        _ => ()
      }
    }
    None => ()
  }
  self.closed = true
  self.pending_responses.close(clear=true)
}
