///|
pub(open) trait Transport {
  receive(Self) -> String? raise @types.TransportError
  send(Self, String) -> Unit raise @types.TransportError
  send_notification(Self, @types.Notification) -> Unit raise @types.TransportError
  send_event(Self, event_type~ : String, data~ : String) -> Unit
  supports_streaming(Self) -> Bool
  close(Self) -> Unit
}

///|
pub(all) enum AnyTransport {
  Stdio(StdioTransport)
  Http(HttpTransport)
}

///|
pub async fn AnyTransport::receive(
  self : AnyTransport,
) -> String? raise @types.TransportError {
  match self {
    Stdio(t) => t.receive()
    Http(t) => t.receive()
  }
}

///|
pub async fn AnyTransport::send(
  self : AnyTransport,
  message : String,
) -> Unit raise @types.TransportError {
  match self {
    Stdio(t) => t.send(message)
    Http(t) => t.send(message)
  }
}

///|
pub async fn AnyTransport::send_notification(
  self : AnyTransport,
  notification : @types.Notification,
) -> Unit raise @types.TransportError {
  match self {
    Stdio(t) => t.send_notification(notification)
    Http(t) => t.send_notification(notification)
  }
}

///|
pub fn AnyTransport::send_event(
  self : AnyTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  match self {
    Stdio(t) => t.send_event(event_type~, data~)
    Http(t) => t.send_event(event_type~, data~)
  }
}

///|
pub fn AnyTransport::supports_streaming(self : AnyTransport) -> Bool {
  match self {
    Stdio(t) => t.supports_streaming()
    Http(t) => t.supports_streaming()
  }
}

///|
pub fn AnyTransport::close(self : AnyTransport) -> Unit {
  match self {
    Stdio(t) => t.close()
    Http(t) => t.close()
  }
}

///|
pub fn validate_jsonrpc_message(
  message : String,
) -> Result[Unit, @types.MCPError] {
  let json = @json.parse(message) catch {
    _ => return Err(@types.ParseError("Invalid JSON"))
  }
  if json is Object(obj) {
    match obj.get("jsonrpc") {
      Some(String("2.0")) => ()
      _ =>
        return Err(@types.InvalidRequest("Missing or invalid 'jsonrpc' field"))
    }
    let has_method = obj.get("method") is Some(_)
    let has_result = obj.get("result") is Some(_)
    let has_error = obj.get("error") is Some(_)
    if not(has_method || has_result || has_error) {
      return Err(
        @types.InvalidRequest("Must have 'method', 'result', or 'error' field"),
      )
    }
    Ok(())
  } else {
    Err(@types.InvalidRequest("JSON-RPC message must be an object"))
  }
}
