///| js stub — server-side transport I/O is not available on this target
/// (per the support matrix: client = native + js, server = native + wasm).
/// HttpClientTransport is absent here: the real implementation in
/// http_client.mbt compiles on js, and so does StdioClientTransport
/// (stdio_client_js.mbt). Everything else declared below aborts,
/// mirroring the wasm-gc stubs in unimplemented.mbt; the declarations
/// suppress only the warnings inherent to abort stubs so js CI can run
/// `--deny-warn`.

///|
/// Not available on js — the stdio server transport requires process pipes.
/// The constructor is intentionally inert (not an abort): connect_*_legacy
/// wraps a Legacy client in a dummy StdioTransport that is never used for
/// I/O — every MCPClient method delegates to the Legacy backend, including
/// close — but an aborting constructor crashed the js target the moment any
/// initialize-era server fell back to legacy. The method stubs below still
/// abort, so the placeholder can never carry real traffic.
#warnings("-struct_never_constructed")
pub struct StdioTransport {
  closed : Bool
}

///|
pub fn StdioTransport::StdioTransport() -> StdioTransport {
  { closed: false, }
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
  keepalive_interval_ms? : Int = 15000,
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
#warnings("-unused_value-unused_async-unused_error_type")
pub async fn HttpTransport::send_notification(
  self : HttpTransport,
  _notification : @types.Notification,
) -> Unit raise @types.TransportError {
  ignore(self)
  abort("HttpTransport is not available on js target")
}

///|
pub fn HttpTransport::set_tool_schema_resolver(
  self : HttpTransport,
  _resolver : (String) -> Json?,
) -> Unit {
  ignore(self)
  abort("HttpTransport is not available on js target")
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
#warnings("-unused_value-unused_async-unused_error_type")
pub async fn HttpTransport::receive_authenticated_request(
  self : HttpTransport,
) -> AuthenticatedRequest? raise @types.TransportError {
  ignore(self)
  abort("HttpTransport is not available on js target")
}

///|
pub fn HttpTransport::close(self : HttpTransport) -> Unit {
  ignore(self)
}
