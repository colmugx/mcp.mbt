///| wasm-gc stub — legacy HTTP session transport relies on @http streaming
/// APIs that moonbitlang/async does not ship for this target, so
/// http_session.mbt is gated out; these abort stubs keep sibling files
/// (legacy_transport.mbt / legacy_client.mbt) compilable.

///|
pub struct LegacyHttpSessionTransport {
  base_url : String
  auth_token : String?
  closed : Bool
}

///|
pub fn LegacyHttpSessionTransport::LegacyHttpSessionTransport(
  url~ : String,
  auth_token? : String = "",
) -> LegacyHttpSessionTransport {
  ignore(url)
  ignore(auth_token)
  abort("LegacyHttpSessionTransport is not available on wasm-gc target")
}

///|
pub async fn LegacyHttpSessionTransport::send(
  self : LegacyHttpSessionTransport,
  _message : String,
) -> Unit raise @types.TransportError {
  ignore(self)
  abort("LegacyHttpSessionTransport is not available on wasm-gc target")
}

///|
pub fn LegacyHttpSessionTransport::receive(
  self : LegacyHttpSessionTransport,
) -> String? {
  ignore(self)
  abort("LegacyHttpSessionTransport is not available on wasm-gc target")
}

///|
pub async fn LegacyHttpSessionTransport::send_notification(
  self : LegacyHttpSessionTransport,
  _notification : @types.Notification,
) -> Unit raise @types.TransportError {
  ignore(self)
  abort("LegacyHttpSessionTransport is not available on wasm-gc target")
}

///|
pub async fn LegacyHttpSessionTransport::close(
  self : LegacyHttpSessionTransport,
) -> Unit {
  ignore(self)
  abort("LegacyHttpSessionTransport is not available on wasm-gc target")
}
