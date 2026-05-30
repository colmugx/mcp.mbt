///|
/// HttpClientTransport — MCP client connecting to a remote HTTP server
/// Uses Streamable HTTP transport (MCP spec): POST for request-response,
/// optional GET SSE for server→client notifications.
pub struct HttpClientTransport {
  base_url : String
  mut session_id : String?
  mut last_response : String?
  mut last_response_status : Int
  mut sse_client : @http.Client?
  mut sse_connected : Bool
  mut closed : Bool
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
  match self.session_id {
    Some(id) => headers["Mcp-Session-Id"] = id
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
/// Returns the JSON payload string, or None if stream ended.
async fn read_sse_event(
  client : @http.Client,
) -> String? raise @types.TransportError {
  let data_lines : Array[String] = []
  while true {
    let line = client.read_until("\n") catch { _ => return None }
    match line {
      None => return None
      Some(l) =>
        if l == "" {
          // Empty line marks end of event
          break
        } else if l.has_prefix("data: ") {
          data_lines.push(l)
        }
      // Ignore other SSE fields (event:, id:, retry:)
    }
  }
  if data_lines.is_empty() {
    None
  } else {
    // Join data lines and strip "data: " prefix
    let mut result = ""
    let mut first = true
    for dl in data_lines {
      if !first {
        result = result + "\n"
      }
      first = false
      let json = dl[6:].to_string() // remove "data: " prefix
      result = result + json
    }
    Some(result)
  }
}

///|
/// POST a JSON-RPC request to the server.
/// Stores the response for subsequent `receive()` call.
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
  match self.session_id {
    Some(id) => headers["Mcp-Session-Id"] = id
    None => ()
  }
  let (response, body) = @http.post(self.base_url, message, headers~) catch {
    e => raise @types.WriteError("HTTP POST failed: \{e}")
  }
  // Extract session ID from response headers (keys are lowercase)
  match response.headers.get("mcp-session-id") {
    Some(id) => self.session_id = Some(id)
    None => ()
  }
  let body_str = body.text() catch {
    e => raise @types.ReadError("Failed to read response body: \{e}")
  }
  self.last_response = Some(body_str)
  self.last_response_status = response.code
}

///|
/// Read response from the last POST, or read next SSE event.
/// Returns None if no response is pending and SSE has no events.
pub async fn HttpClientTransport::receive(
  self : HttpClientTransport,
) -> String? raise @types.TransportError {
  if self.closed {
    return None
  }
  // Priority 1: return stored POST response
  match self.last_response {
    Some(body) => {
      self.last_response = None
      return Some(body)
    }
    None => ()
  }
  // Priority 2: read from SSE stream
  match self.sse_client {
    Some(client) => {
      let event_opt = read_sse_event(client)
      match event_opt {
        Some(event_json) => {
          // Parse to check if it's a response (has id) or notification (no id)
          let json = @json.parse(event_json) catch { _ => return None }
          match json {
            Object(obj) => {
              let has_id = obj.get("id") is Some(_)
              if has_id {
                // This is a JSON-RPC response — return it
                Some(event_json)
              } else {
                // This is a notification — return raw JSON for
                // the client layer to dispatch
                Some(event_json)
              }
            }
            _ => None
          }
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
  match self.session_id {
    Some(id) => headers["Mcp-Session-Id"] = id
    None => ()
  }
  let (_response, _body) = @http.post(self.base_url, json_body, headers~) catch {
    e => raise @types.WriteError("Failed to send notification: \{e}")
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
  match self.sse_client {
    Some(client) => client.close()
    None => ()
  }
  self.sse_client = None
  self.sse_connected = false
  self.closed = true
  self.session_id = None
}
