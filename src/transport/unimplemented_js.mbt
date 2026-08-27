///| js stub — server-side transport I/O is not available on this target
/// (per the support matrix: client = native + js, server = native + wasm).
/// HttpClientTransport is absent here: the real implementation in
/// http_client.mbt compiles on js, and so does StdioClientTransport
/// (stdio_client_js.mbt). Everything else declared below aborts,
/// mirroring the wasm-gc stubs in unimplemented.mbt; the declarations
/// suppress only the warnings inherent to abort stubs so js CI can run
/// `--deny-warn`.

///|
/// Server-side authentication configuration (MCP spec 2026-07-28).
#warnings("-struct_never_constructed")
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
  ignore(verify_token)
  ignore(resource_metadata_url)
  ignore(authorization_servers)
  ignore(required_scopes)
  ignore(allowed_origins)
  abort("AuthConfig is not available on js target")
}

///|
/// Not available on js — the stdio server transport requires process pipes.
#warnings("-struct_never_constructed")
pub struct StdioTransport {
  closed : Bool
}

///|
pub fn StdioTransport::StdioTransport() -> StdioTransport {
  abort("StdioTransport is not available on js target")
}

///|
#warnings("-unused_async-unused_error_type")
pub async fn StdioTransport::receive(
  self : StdioTransport,
) -> String? raise @types.TransportError {
  ignore(self)
  abort("StdioTransport is not available on js target")
}

///|
#warnings("-unused_async-unused_error_type")
pub async fn StdioTransport::send(
  self : StdioTransport,
  _message : String,
) -> Unit raise @types.TransportError {
  ignore(self)
  abort("StdioTransport is not available on js target")
}

///|
#warnings("-unused_async-unused_error_type")
pub async fn StdioTransport::send_notification(
  self : StdioTransport,
  _notification : @types.Notification,
) -> Unit raise @types.TransportError {
  ignore(self)
  abort("StdioTransport is not available on js target")
}

///|
#warnings("-struct_never_constructed")
pub fn StdioTransport::send_event(
  self : StdioTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  ignore(self)
  ignore(event_type)
  ignore(data)
  abort("StdioTransport is not available on js target")
}

///|
pub fn StdioTransport::supports_streaming(_self : StdioTransport) -> Bool {
  abort("StdioTransport is not available on js target")
}

///|
pub fn StdioTransport::close(self : StdioTransport) -> Unit {
  ignore(self)
  abort("StdioTransport is not available on js target")
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
pub fn HttpTransport::close(self : HttpTransport) -> Unit {
  ignore(self)
}
