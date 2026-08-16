///| wasm-gc stub — transport I/O not available on this target

///|
pub struct AuthConfig {
  verify_token : (String) -> Bool
  resource_metadata_url : String
  authorization_servers : Array[String]
  required_scopes : String?
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
  abort("AuthConfig is not available on wasm-gc target")
}

///|
pub struct StdioTransport {
  closed : Bool
}

///|
pub fn StdioTransport::StdioTransport() -> StdioTransport {
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
  auth : AuthConfig?
}

///|
pub fn HttpTransport::HttpTransport(
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
pub fn HttpTransport::with_auth(
  self : HttpTransport,
  _auth : AuthConfig,
) -> HttpTransport {
  ignore(self)
  abort("HttpTransport is not available on wasm-gc target")
}

///|
pub async fn HttpTransport::receive_request(
  self : HttpTransport,
) -> (String, @async.Queue[String])? raise @types.TransportError {
  ignore(self)
  abort("HttpTransport is not available on wasm-gc target")
}

///|
pub fn HttpTransport::close(self : HttpTransport) -> Unit {
  abort("HttpTransport is not available on wasm-gc target")
}

///|
pub struct StdioClientTransport {
  closed : Bool
}

///|
pub fn StdioClientTransport::StdioClientTransport(
  cmd~ : String,
  args? : Array[String] = [],
  extra_env? : Map[String, String] = {},
) -> StdioClientTransport {
  abort("StdioClientTransport is not available on wasm-gc target")
}

///|
pub async fn StdioClientTransport::start(
  self : StdioClientTransport,
  group : @async.TaskGroup[Unit],
) -> Unit raise @types.TransportError {
  abort("StdioClientTransport is not available on wasm-gc target")
}

///|
pub async fn StdioClientTransport::receive(
  self : StdioClientTransport,
) -> String? raise @types.TransportError {
  abort("StdioClientTransport is not available on wasm-gc target")
}

///|
pub async fn StdioClientTransport::send(
  self : StdioClientTransport,
  _message : String,
) -> Unit raise @types.TransportError {
  abort("StdioClientTransport is not available on wasm-gc target")
}

///|
pub async fn StdioClientTransport::send_notification(
  self : StdioClientTransport,
  _notification : @types.Notification,
) -> Unit raise @types.TransportError {
  abort("StdioClientTransport is not available on wasm-gc target")
}

///|
pub fn StdioClientTransport::send_event(
  _self : StdioClientTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  abort("StdioClientTransport is not available on wasm-gc target")
}

///|
pub fn StdioClientTransport::supports_streaming(
  _self : StdioClientTransport,
) -> Bool {
  abort("StdioClientTransport is not available on wasm-gc target")
}

///|
pub fn StdioClientTransport::close(self : StdioClientTransport) -> Unit {
  abort("StdioClientTransport is not available on wasm-gc target")
}

///| wasm-gc stub — HttpClientTransport not available on this target

///|
pub struct HttpClientTransport {
  base_url : String
  auth_token : String?
  closed : Bool
}

///|
pub fn HttpClientTransport::HttpClientTransport(
  base_url : String,
  auth_token? : String = "",
) -> HttpClientTransport {
  ignore(base_url)
  ignore(auth_token)
  abort("HttpClientTransport is not available on wasm-gc target")
}

///|
pub fn HttpClientTransport::set_tool_header_schemas(
  self : HttpClientTransport,
  _schemas : Map[String, Array[(Array[String], String)]],
) -> Unit {
  ignore(self)
  abort("HttpClientTransport is not available on wasm-gc target")
}

///|
pub async fn HttpClientTransport::receive(
  self : HttpClientTransport,
) -> String? noraise {
  ignore(self)
  abort("HttpClientTransport is not available on wasm-gc target")
}

///|
pub async fn HttpClientTransport::send(
  self : HttpClientTransport,
  _message : String,
) -> Unit raise @types.TransportError {
  abort("HttpClientTransport is not available on wasm-gc target")
}

///|
pub async fn HttpClientTransport::send_notification(
  self : HttpClientTransport,
  _notification : @types.Notification,
) -> Unit raise @types.TransportError {
  abort("HttpClientTransport is not available on wasm-gc target")
}

///|
pub fn HttpClientTransport::send_event(
  _self : HttpClientTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  abort("HttpClientTransport is not available on wasm-gc target")
}

///|
pub fn HttpClientTransport::supports_streaming(
  _self : HttpClientTransport,
) -> Bool {
  abort("HttpClientTransport is not available on wasm-gc target")
}

///|
pub fn HttpClientTransport::close(self : HttpClientTransport) -> Unit {
  abort("HttpClientTransport is not available on wasm-gc target")
}
