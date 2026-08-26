///| js stub — transport I/O is not available on this target.
/// HttpClientTransport is absent here: the real implementation in
/// http_client.mbt compiles on js.
///
/// Pure-data / pure-logic members (AuthConfig entirely; StdioTransport
/// construction and closed-state bookkeeping) keep their real behavior so
/// client/server construction and field tests run on js. Everything touching
/// stdio/process/socket aborts; those declarations suppress only the
/// warnings inherent to abort stubs so js CI can run `--deny-warn`.

///|
/// Server-side authentication configuration (MCP spec 2026-07-28).
/// Pure data — identical to the native implementation in http_server.mbt.
pub struct AuthConfig {
  /// Validate a Bearer token. Return true if the token is valid.
  verify_token : (String) -> Bool
  /// URL of this resource for WWW-Authenticate and metadata responses.
  resource_metadata_url : String
  /// Authorization server URLs for Protected Resource Metadata (RFC 9728).
  authorization_servers : Array[String]
  /// Required scopes (e.g. "mcp:read mcp:write"). None = no scope check.
  required_scopes : String?
  /// Allowed Origins for DNS rebinding prevention. None = allow all.
  allowed_origins : Array[String]?
}

///|
pub fn AuthConfig::AuthConfig(
  verify_token~ : (String) -> Bool,
  resource_metadata_url~ : String,
  authorization_servers? : Array[String] = [],
  required_scopes? : String = "",
  allowed_origins? : Array[String] = [],
) -> AuthConfig {
  {
    verify_token,
    resource_metadata_url,
    authorization_servers,
    required_scopes: if required_scopes == "" {
      None
    } else {
      Some(required_scopes)
    },
    allowed_origins: if allowed_origins.is_empty() {
      None
    } else {
      Some(allowed_origins)
    },
  }
}

///|
/// Construction and closed-state bookkeeping are real (pure logic); the
/// reader/writer fields of the native struct do not exist on js.
pub struct StdioTransport {
  mut closed : Bool
}

///|
pub fn StdioTransport::StdioTransport() -> StdioTransport {
  { closed: false }
}

///|
#warnings("-unused_async-unused_error_type")
pub async fn StdioTransport::receive(
  self : StdioTransport,
) -> String? raise @types.TransportError {
  ignore(self)
  abort("StdioTransport::receive is not available on js target")
}

///|
#warnings("-unused_value-unused_async-unused_error_type")
pub async fn StdioTransport::send(
  self : StdioTransport,
  _message : String,
) -> Unit raise @types.TransportError {
  ignore(self)
  abort("StdioTransport::send is not available on js target")
}

///|
/// No-op, identical to the native implementation.
pub fn StdioTransport::send_event(
  _self : StdioTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  ignore(event_type)
  ignore(data)
  ()
}

///|
#warnings("-unused_async-unused_error_type")
pub async fn StdioTransport::send_notification(
  self : StdioTransport,
  _notification : @types.Notification,
) -> Unit raise @types.TransportError {
  ignore(self)
  abort("StdioTransport::send_notification is not available on js target")
}

///|
pub fn StdioTransport::supports_streaming(_self : StdioTransport) -> Bool {
  false
}

///|
/// Real (pure logic), identical to the native implementation.
pub fn StdioTransport::close(self : StdioTransport) -> Unit {
  if !self.closed {
    self.closed = true
  }
}

///|
#warnings("-struct_never_constructed")
pub struct HttpTransport {
  port : Int
  endpoint_path : String
  auth : AuthConfig?
}

///|
#warnings("-unused_value")
pub fn HttpTransport::HttpTransport(
  port? : Int = 4240,
  endpoint_path? : String = "/mcp",
) -> HttpTransport {
  abort("HttpTransport is not available on js target")
}

///|
#warnings("-unused_value-unused_async-unused_error_type")
pub async fn HttpTransport::start(
  self : HttpTransport,
) -> Unit raise @types.TransportError {
  ignore(self)
  abort("HttpTransport is not available on js target")
}

///|
#warnings("-unused_value-unused_async-unused_error_type")
pub async fn HttpTransport::receive(
  self : HttpTransport,
) -> String? raise @types.TransportError {
  ignore(self)
  abort("HttpTransport is not available on js target")
}

///|
#warnings("-unused_value-unused_async-unused_error_type")
pub async fn HttpTransport::send(
  self : HttpTransport,
  _message : String,
) -> Unit raise @types.TransportError {
  ignore(self)
  abort("HttpTransport is not available on js target")
}

///|
#warnings("-unused_value")
pub fn HttpTransport::send_event(
  self : HttpTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  ignore(self)
  ignore(event_type)
  ignore(data)
  ()
}

///|
#warnings("-unused_value-unused_async-unused_error_type")
pub async fn HttpTransport::send_notification(
  self : HttpTransport,
  _notification : @types.Notification,
) -> Unit raise @types.TransportError {
  ignore(self)
  abort("HttpTransport is not available on js target")
}

///|
/// No-op, identical to the native implementation.
pub fn HttpTransport::supports_streaming(_self : HttpTransport) -> Bool {
  true
}

///|
#warnings("-unused_value")
pub fn HttpTransport::with_auth(
  self : HttpTransport,
  _auth : AuthConfig,
) -> HttpTransport {
  ignore(self)
  abort("HttpTransport is not available on js target")
}

///|
#warnings("-unused_value-unused_async-unused_error_type")
pub async fn HttpTransport::receive_request(
  self : HttpTransport,
) -> (String, @async.Queue[String])? raise @types.TransportError {
  ignore(self)
  abort("HttpTransport is not available on js target")
}

///|
/// No-op, identical to the native implementation.
pub fn HttpTransport::close(self : HttpTransport) -> Unit {
  ignore(self)
}

///|
#warnings("-struct_never_constructed")
pub struct StdioClientTransport {
  closed : Bool
}

///|
#warnings("-unused_value")
pub fn StdioClientTransport::StdioClientTransport(
  cmd~ : String,
  args? : Array[String] = [],
  extra_env? : Map[String, String] = {},
) -> StdioClientTransport {
  abort("StdioClientTransport is not available on js target")
}

///|
#warnings("-unused_value-unused_async-unused_error_type")
pub async fn StdioClientTransport::start(
  self : StdioClientTransport,
  group : @async.TaskGroup[Unit],
) -> Unit raise @types.TransportError {
  ignore(self)
  ignore(group)
  abort("StdioClientTransport is not available on js target")
}

///|
#warnings("-unused_value-unused_async-unused_error_type")
pub async fn StdioClientTransport::receive(
  self : StdioClientTransport,
) -> String? raise @types.TransportError {
  ignore(self)
  abort("StdioClientTransport is not available on js target")
}

///|
#warnings("-unused_value-unused_async-unused_error_type")
pub async fn StdioClientTransport::send(
  self : StdioClientTransport,
  _message : String,
) -> Unit raise @types.TransportError {
  ignore(self)
  abort("StdioClientTransport is not available on js target")
}

///|
#warnings("-unused_value-unused_async-unused_error_type")
pub async fn StdioClientTransport::send_notification(
  self : StdioClientTransport,
  _notification : @types.Notification,
) -> Unit raise @types.TransportError {
  ignore(self)
  abort("StdioClientTransport is not available on js target")
}

///|
#warnings("-unused_value")
pub fn StdioClientTransport::send_event(
  _self : StdioClientTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  ignore(event_type)
  ignore(data)
  ()
}

///|
/// No-op, identical to the native implementation.
pub fn StdioClientTransport::supports_streaming(
  _self : StdioClientTransport,
) -> Bool {
  false
}

///|
#warnings("-unused_value")
pub fn StdioClientTransport::close(self : StdioClientTransport) -> Unit {
  ignore(self)
  abort("StdioClientTransport is not available on js target")
}
