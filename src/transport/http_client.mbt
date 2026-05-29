///|
/// HttpClientTransport — MCP client 连接到远程 HTTP server
pub struct HttpClientTransport {
  base_url : String
  mut session_id : String?
  mut closed : Bool
}

///|
pub fn HttpClientTransport::new(base_url : String) -> HttpClientTransport {
  { base_url, session_id: None, closed: false }
}

///|
/// POST JSON-RPC request to server
pub async fn HttpClientTransport::receive(
  self : HttpClientTransport,
) -> String? raise @types.TransportError {
  None
}

///|
/// Read response from server
pub async fn HttpClientTransport::send(
  self : HttpClientTransport,
  message : String,
) -> Unit raise @types.TransportError {
  abort(
    "HttpClientTransport.send: HTTP client not yet implemented in moonbitlang/async",
  )
}

///|
pub async fn HttpClientTransport::send_notification(
  self : HttpClientTransport,
  _notification : @types.Notification,
) -> Unit raise @types.TransportError {
  abort("HttpClientTransport.send_notification: not yet implemented")
}

///|
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
  self.session_id = None
}
