///|
/// Internal transport wrapper for `LegacyClient`.
///
/// `LegacyClient` must be able to accept a modern `@transport.AnyTransport` (for
/// callers that already have one) or the legacy session-aware HTTP transport (for
/// `connect_http`). This private enum keeps both shapes inside the legacy package
/// without adding a variant to the closed `AnyTransport` enum in the transport
/// package.
pub enum LegacyTransport {
  Wrapped(@transport.AnyTransport)
  HttpSession(LegacyHttpSessionTransport)
}

///|
async fn LegacyTransport::send(
  self : LegacyTransport,
  message : String,
) -> Unit raise @types.TransportError {
  match self {
    Wrapped(t) => t.send(message)
    HttpSession(t) => t.send(message)
  }
}

///|
async fn LegacyTransport::receive(
  self : LegacyTransport,
) -> String? raise @types.TransportError {
  match self {
    Wrapped(t) => t.receive()
    HttpSession(t) => t.receive()
  }
}

///|
async fn LegacyTransport::send_notification(
  self : LegacyTransport,
  notification : @types.Notification,
) -> Unit raise @types.TransportError {
  match self {
    Wrapped(t) => t.send_notification(notification)
    HttpSession(t) => t.send_notification(notification)
  }
}

///|
async fn LegacyTransport::close(self : LegacyTransport) -> Unit {
  match self {
    Wrapped(t) => t.close()
    HttpSession(t) => t.close()
  }
}
