///| wasm-gc stub — transport I/O not available on this target

///|
pub struct StdioTransport {
  closed : Bool
}

///|
pub fn StdioTransport::new() -> StdioTransport {
  abort("StdioTransport is not available on wasm-gc target")
}

///|
pub async fn StdioTransport::receive(
  self : StdioTransport,
) -> String? raise @types.TransportError {
  abort("StdioTransport is not available on wasm-gc target")
}

///|
pub async fn StdioTransport::send(
  self : StdioTransport,
  _message : String,
) -> Unit raise @types.TransportError {
  abort("StdioTransport is not available on wasm-gc target")
}

///|
pub fn StdioTransport::send_event(
  self : StdioTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  abort("StdioTransport is not available on wasm-gc target")
}

///|
pub async fn StdioTransport::send_notification(
  self : StdioTransport,
  _notification : @types.Notification,
) -> Unit raise @types.TransportError {
  abort("StdioTransport is not available on wasm-gc target")
}

///|
pub fn StdioTransport::supports_streaming(_self : StdioTransport) -> Bool {
  abort("StdioTransport is not available on wasm-gc target")
}

///|
pub fn StdioTransport::close(self : StdioTransport) -> Unit {
  abort("StdioTransport is not available on wasm-gc target")
}

///|
pub struct HttpTransport {
  port : Int
  endpoint_path : String
}

///|
pub fn HttpTransport::new(
  port? : Int = 4240,
  endpoint_path? : String = "/mcp",
) -> HttpTransport {
  abort("HttpTransport is not available on wasm-gc target")
}

///|
pub async fn HttpTransport::start(
  self : HttpTransport,
) -> Unit raise @types.TransportError {
  abort("HttpTransport is not available on wasm-gc target")
}

///|
pub async fn HttpTransport::receive(
  self : HttpTransport,
) -> String? raise @types.TransportError {
  abort("HttpTransport is not available on wasm-gc target")
}

///|
pub async fn HttpTransport::send(
  self : HttpTransport,
  _message : String,
) -> Unit raise @types.TransportError {
  abort("HttpTransport is not available on wasm-gc target")
}

///|
pub fn HttpTransport::send_event(
  self : HttpTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  abort("HttpTransport is not available on wasm-gc target")
}

///|
pub async fn HttpTransport::send_notification(
  self : HttpTransport,
  _notification : @types.Notification,
) -> Unit raise @types.TransportError {
  abort("HttpTransport is not available on wasm-gc target")
}

///|
pub fn HttpTransport::supports_streaming(_self : HttpTransport) -> Bool {
  abort("HttpTransport is not available on wasm-gc target")
}

///|
pub fn HttpTransport::close(self : HttpTransport) -> Unit {
  abort("HttpTransport is not available on wasm-gc target")
}
