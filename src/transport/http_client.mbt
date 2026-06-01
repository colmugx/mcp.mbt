///|
/// HttpClientTransport — MCP client connecting to a remote HTTP server
/// Uses Streamable HTTP transport (MCP spec 2025-11-25): POST for
/// request-response, optional GET SSE for server→client notifications.
pub struct HttpClientTransport {
  base_url : String
  mut session_id : String?
  mut last_response : String?
  mut last_response_status : Int
  mut sse_client : @http.Client?
  mut sse_connected : Bool
  mut closed : Bool
  mut last_event_id : String?
  mut sse_pending_responses : Array[String]?
  mut sse_pending_index : Int
  protocol_version : String
}

///|
pub fn HttpClientTransport::new(base_url : String) -> HttpClientTransport {
  {
    base_url,
    session_id: None,
    last_response: None,
    last_response_status: 0,
    sse_client: None,
    sse_connected: false,
    closed: false,
    last_event_id: None,
    sse_pending_responses: None,
    sse_pending_index: 0,
    protocol_version: "2025-11-25",
  }
}

///|
/// Establish SSE subscription channel for server→client notifications.
/// Called lazily on first `send()` if not already connected.
async fn HttpClientTransport::establish_sse(
  self : HttpClientTransport,
) -> Unit raise @types.TransportError {
  let headers : Map[String, String] = {}
  headers["Accept"] = "text/event-stream"
  headers["Cache-Control"] = "no-cache"
  headers["MCP-Protocol-Version"] = self.protocol_version
  match self.session_id {
    Some(id) => headers["Mcp-Session-Id"] = id
    None => ()
  }
  match self.last_event_id {
    Some(id) => headers["Last-Event-ID"] = id
    None => ()
  }
  let (response, client) = @http.get_stream(self.base_url, headers~) catch {
    e => raise @types.WriteError("SSE connection failed: \{e}")
  }
  guard response.code is (200..<300) else {
    client.close()
    raise @types.WriteError(
      "SSE connection failed: HTTP \{response.code} \{response.reason}",
    )
  }
  self.sse_client = Some(client)
  self.sse_connected = true
}

///|
/// Parse one SSE event from the streaming client.
/// Returns (json_payload, event_id) — event_id is None if no `id:` field.
async fn read_sse_event(
  client : @http.Client,
) -> (String?, String?) raise @types.TransportError {
  let data_lines : Array[String] = []
  let mut event_id : String? = None
  while true {
    let line = client.read_until("\n") catch { _ => return (None, None) }
    match line {
      None => return (None, None)
      Some(l) =>
        if l == "" {
          // Empty line marks end of event
          break
        } else if l.has_prefix("data: ") {
          data_lines.push(l)
        } else if l.has_prefix("id: ") {
          event_id = Some(l[4:].trim().to_owned())
        }
      // Ignore other SSE fields (event:, retry:)
    }
  }
  if data_lines.is_empty() {
    (None, event_id)
  } else {
    // Join data lines and strip "data: " prefix
    let mut result = ""
    let mut first = true
    for dl in data_lines {
      if !first {
        result = result + "\n"
      }
      first = false
      let json = dl[6:].to_owned() // remove "data: " prefix
      result = result + json
    }
    (Some(result), event_id)
  }
}

///|
/// POST a JSON-RPC request to the server using streaming HTTP.
/// Handles both single JSON and SSE streaming responses per MCP spec.
pub async fn HttpClientTransport::send(
  self : HttpClientTransport,
  message : String,
) -> Unit raise @types.TransportError {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }
  // Lazy SSE establishment
  if !self.sse_connected {
    self.establish_sse()
  }
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  headers["Accept"] = "application/json, text/event-stream"
  headers["MCP-Protocol-Version"] = self.protocol_version
  match self.session_id {
    Some(id) => headers["Mcp-Session-Id"] = id
    None => ()
  }
  // Use post_stream for spec-compliant response handling
  let client = @http.post_stream(self.base_url, headers~) catch {
    e => raise @types.WriteError("HTTP POST failed: \{e}")
  }
  // Write request body
  client.write(message.to_bytes()) catch {
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
  // Get response headers + status
  let response = client.end_request() catch {
    e => {
      client.close()
      raise @types.ReadError("Failed to get response: \{e}")
    }
  }
  // Extract session ID from response headers (keys are lowercase)
  match response.headers.get("mcp-session-id") {
    Some(id) => self.session_id = Some(id)
    None => ()
  }
  self.last_response_status = response.code
  // Handle HTTP 404 → session expired, re-initialize
  if response.code == 404 {
    client.close()
    raise @types.InvalidState(
      "Server returned 404 — session expired, re-initialize",
    )
  }
  // Determine response mode from Content-Type
  let content_type = match response.headers.get("content-type") {
    Some(ct) => ct.to_lower()
    None => "application/json"
  }
  if content_type.contains("text/event-stream") {
    // SSE response: read events from streaming body
    let accumulated : Array[String] = []
    while true {
      let (data_opt, id_opt) = read_sse_event(client) catch { _ => break }
      match id_opt {
        Some(id) => self.last_event_id = Some(id)
        None => ()
      }
      match data_opt {
        Some(event_json) => accumulated.push(event_json)
        None => break
      }
    }
    client.close() catch {
      _ => ()
    }
    if !accumulated.is_empty() {
      self.sse_pending_responses = Some(accumulated)
      self.sse_pending_index = 0
    }
  } else {
    // Single JSON response: read entire body
    let body = client.read_all() catch {
      e => {
        client.close()
        raise @types.ReadError("Failed to read response body: \{e}")
      }
    }
    client.close() catch {
      _ => ()
    }
    let body_str = body.text() catch {
      e => raise @types.ReadError("Failed to read response body: \{e}")
    }
    self.last_response = Some(body_str)
  }
}

///|
/// Read response: drain SSE POST events, then stored POST JSON, then SSE GET.
/// Returns None if no response is pending and SSE has no events.
pub async fn HttpClientTransport::receive(
  self : HttpClientTransport,
) -> String? raise @types.TransportError {
  if self.closed {
    return None
  }
  // Priority 0: return SSE events from POST response (index-based FIFO)
  match self.sse_pending_responses {
    Some(events) => {
      let idx = self.sse_pending_index
      if idx < events.length() {
        let event = events[idx]
        self.sse_pending_index = idx + 1
        return Some(event)
      } else {
        self.sse_pending_responses = None
        self.sse_pending_index = 0
      }
    }
    None => ()
  }
  // Priority 1: return stored POST response
  match self.last_response {
    Some(body) => {
      self.last_response = None
      return Some(body)
    }
    None => ()
  }
  // Priority 2: read from SSE GET stream
  match self.sse_client {
    Some(client) => {
      let (data_opt, id_opt) = read_sse_event(client)
      match id_opt {
        Some(id) => self.last_event_id = Some(id)
        None => ()
      }
      match data_opt {
        Some(event_json) => {
          // Validate it's parseable JSON — return as-is for client dispatch
          let _ = @json.parse(event_json) catch { _ => return None }
          Some(event_json)
        }
        None => None
      }
    }
    None => None
  }
}

///|
/// Send a JSON-RPC notification (no id, fire-and-forget).
pub async fn HttpClientTransport::send_notification(
  self : HttpClientTransport,
  notification : @types.Notification,
) -> Unit raise @types.TransportError {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }
  let json_body = @jsonutil.jsonrpc_notification(
    notification.method_name,
    notification.params,
  )
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  headers["MCP-Protocol-Version"] = self.protocol_version
  match self.session_id {
    Some(id) => headers["Mcp-Session-Id"] = id
    None => ()
  }
  // Use post_stream — server may respond with SSE even for notifications
  let client = @http.post_stream(self.base_url, headers~) catch {
    e => raise @types.WriteError("Failed to send notification: \{e}")
  }
  // Fire-and-forget: write body, end request, close
  try {
    client.write(json_body.to_bytes())
    client.flush()
    let _ = client.end_request()
  } catch {
    _ => ()
  }
  client.close() catch {
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
/// Gracefully close the HTTP session by sending a DELETE request.
/// Call this before `close()` for proper session termination.
pub async fn HttpClientTransport::close_session(
  self : HttpClientTransport,
) -> Unit {
  if self.closed {
    return
  }
  match self.session_id {
    Some(_) => {
      let headers : Map[String, String] = {}
      headers["MCP-Protocol-Version"] = self.protocol_version
      match self.session_id {
        Some(id) => headers["Mcp-Session-Id"] = id
        None => ()
      }
      // Best-effort DELETE — wrap entire operation in try
      try {
        let client = @http.Client(self.base_url, headers~)
        defer client.close()
        client.request(@http.Delete, "/")
        let _ = client.end_request()
      } catch {
        _ => ()
      }
    }
    None => ()
  }
  self.close()
}

///|
pub fn HttpClientTransport::close(self : HttpClientTransport) -> Unit {
  match self.sse_client {
    Some(client) => client.close()
    None => ()
  }
  self.sse_client = None
  self.sse_connected = false
  self.closed = true
  self.session_id = None
}
