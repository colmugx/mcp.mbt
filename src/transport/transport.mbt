///|
pub(open) trait Transport {
  fn receive(Self) -> String? raise @types.TransportError
  fn send(Self, String) -> Unit raise @types.TransportError
  fn send_notification(Self, @types.Notification) -> Unit raise @types.TransportError
  fn close(Self) -> Unit
}

///|
pub(all) enum AnyTransport {
  Stdio(StdioTransport)
  StdioClient(StdioClientTransport)
  Http(HttpTransport)
  HttpClient(HttpClientTransport)
}

///|
pub async fn AnyTransport::receive(self : AnyTransport) -> String? {
  match self {
    Stdio(t) => t.receive()
    StdioClient(t) => t.receive()
    Http(t) => t.receive()
    HttpClient(t) => t.receive()
  }
}

///|
/// Receive both the original wire text and its decoded JSON value. HTTP client
/// transports validate and decode responses while collecting their body, so
/// this path reuses that value instead of parsing the same event a second time.
pub async fn AnyTransport::receive_decoded(
  self : AnyTransport,
) -> (String, Json)? {
  match self {
    HttpClient(t) => t.receive_decoded()
    _ =>
      match self.receive() {
        Some(raw) => {
          let parsed = @json.parse(raw) catch { _ => Json::null() }
          Some((raw, parsed))
        }
        None => None
      }
  }
}

///|
pub async fn AnyTransport::send(self : AnyTransport, message : String) -> Unit {
  match self {
    Stdio(t) => t.send(message)
    StdioClient(t) => t.send(message)
    Http(t) => t.send(message)
    HttpClient(t) => t.send(message)
  }
}

///|
/// Send a structured JSON-RPC message. Serialization happens once, at the
/// transport boundary; client code can keep the request as a Json value.
pub async fn AnyTransport::send_json(
  self : AnyTransport,
  message : Json,
) -> Unit {
  match self {
    Stdio(t) => t.send(message.stringify())
    StdioClient(t) => t.send_json(message)
    Http(t) => t.send(message.stringify())
    HttpClient(t) => t.send_json(message)
  }
}

///|
pub async fn AnyTransport::send_notification(
  self : AnyTransport,
  notification : @types.Notification,
) -> Unit {
  match self {
    Stdio(t) => t.send_notification(notification)
    StdioClient(t) => t.send_notification(notification)
    Http(t) => t.send_notification(notification)
    HttpClient(t) => t.send_notification(notification)
  }
}

///|
pub fn AnyTransport::close(self : AnyTransport) -> Unit {
  match self {
    Stdio(t) => t.close()
    StdioClient(t) => t.close()
    Http(t) => t.close()
    HttpClient(t) => t.close()
  }
}

///|
fn validate_jsonrpc_value(json : Json) -> Unit raise @types.MCPError {
  if json is Object(obj) {
    match obj.get("jsonrpc") {
      Some(String("2.0")) => ()
      _ => raise @types.InvalidRequest("Missing or invalid 'jsonrpc' field")
    }
    let has_method = obj.get("method") is Some(_)
    let has_result = obj.get("result") is Some(_)
    let has_error = obj.get("error") is Some(_)
    if !(has_method || has_result || has_error) {
      raise @types.InvalidRequest(
        "Must have 'method', 'result', or 'error' field",
      )
    }
    ()
  } else {
    raise @types.InvalidRequest("JSON-RPC message must be an object")
  }
}

///|
/// Validate raw JSON-RPC input by decoding it once and checking the decoded
/// envelope. Structured callers use validate_jsonrpc_value directly.
pub fn validate_jsonrpc_message(message : String) -> Unit raise @types.MCPError {
  let json = @json.parse(message) catch {
    _ => raise @types.ParseError("Invalid JSON")
  }
  validate_jsonrpc_value(json)
}
