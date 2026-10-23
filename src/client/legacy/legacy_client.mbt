///| Legacy client for the 2025-11-25 protocol era.
///
/// The modern `MCPClient` speaks the stateless 2026-07-28 protocol: no
/// initialize handshake, per-request `_meta`. When a deployment must talk to
/// an older server that still expects the legacy `initialize`/session flow,
/// it can probe the server's era first (modern `server/discover` succeeds →
/// modern; non-modern error/timeout → legacy) and fall back to this client.
///
/// `LegacyClient` owns the legacy `initialize` + `notifications/initialized`
/// handshake and the session-aware transport concerns that the modern client
/// has shed. It depends only on `transport` and `protocol/types` — it never
/// imports the modern `client` package, so deleting this directory when the
/// ecosystem has migrated is a clean cut.
///
/// Scope of this module: the handshake and a minimal request send/receive
/// loop. Era probing and ClientBackend dispatch live in the modern client
/// (`client/era_probe.mbt` drives the probe; `MCPClient` holds the
/// `ClientBackend` enum) and decide when to construct a LegacyClient.

///|
/// Protocol version this legacy client advertises during initialize.
let legacy_protocol_version : String = "2025-11-25"

///|
pub struct LegacyClient {
  client_name : String
  client_version : String
  transport : LegacyTransport
  /// Legacy exchanges have no response-id dispatcher: a full send/receive
  /// pair must own the transport, or two concurrent requests can both read
  /// the same stdio pipe (and receive each other's responses).
  request_mutex : @async.Mutex
  mut next_id : Int32
  mut server_name : String
  mut server_version : String
}

///|
pub fn LegacyClient::LegacyClient(
  name~ : String,
  version~ : String,
  transport~ : @transport.AnyTransport,
) -> LegacyClient {
  {
    client_name: name,
    client_version: version,
    transport: LegacyTransport::Wrapped(transport),
    request_mutex: @async.Mutex::Mutex(),
    next_id: 0,
    server_name: "unknown",
    server_version: "unknown",
  }
}

///|
fn LegacyClient::next_request_id(self : LegacyClient) -> Int32 {
  self.next_id = self.next_id + 1
  self.next_id
}

///|
/// Parse the `InitializeResult` response into `ServerInfo`.
fn parse_initialize_response(
  response : String,
) -> @types.ServerInfo raise @types.MCPError {
  let json = @json.parse(response) catch {
    _ => raise @types.ParseError("Invalid initialize response")
  }
  match json {
    Object(obj) =>
      match obj.get("result") {
        Some(Object(result)) =>
          match result.get("serverInfo") {
            Some(Object(info)) => {
              let name = match info.get("name") {
                Some(String(n)) => n
                _ => "unknown"
              }
              let version = match info.get("version") {
                Some(String(v)) => v
                _ => "unknown"
              }
              { name, title: None, version, description: None, }
            }
            _ =>
              {
                name: "unknown",
                title: None,
                version: "unknown",
                description: None,
              }
          }
        _ => raise @types.InvalidRequest("initialize response missing result")
      }
    _ => raise @types.ParseError("initialize response is not an object")
  }
}

///|
/// Perform the legacy initialize handshake: send `initialize`, parse
/// `serverInfo`/`protocolVersion` from the response, then send
/// `notifications/initialized`. Returns the server identity on success.
///
/// The legacy client advertises empty client capabilities: it has no inbound
/// request handlers (roots/listChanged and sampling are provided by the modern
/// client after the 2026-07-28 migration), so claiming them here would be a lie.
pub async fn LegacyClient::initialize(self : LegacyClient) -> @types.ServerInfo {
  self.request_mutex.acquire()
  defer self.request_mutex.release()
  let id = self.next_request_id()
  // Build the initialize request body for the 2025-11-25 shape.
  // Capabilities are intentionally empty: this fallback client cannot serve
  // inbound roots/listChanged or sampling requests.
  let caps : Map[String, Json] = Map([])
  let request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("initialize"),
    "params": Json::object({
      "protocolVersion": Json::string(legacy_protocol_version),
      "capabilities": Json::object(caps),
      "clientInfo": Json::object({
        "name": Json::string(self.client_name),
        "version": Json::string(self.client_version),
      }),
    }),
  }).stringify()
  // Send + receive (legacy synchronous send/receive on the transport).
  let t = self.transport
  t.send(request) catch {
    e => raise @types.InternalError("Send failed: " + e.to_string())
  }
  let response = t.receive() catch {
    e => raise @types.InternalError("Receive failed: " + e.to_string())
  }
  let response_str = match response {
    Some(s) => s
    None => raise @types.InternalError("Connection closed during initialize")
  }
  let info = parse_initialize_response(response_str)
  self.server_name = info.name
  self.server_version = info.version
  // Send notifications/initialized to complete the handshake.
  let notification = @types.Notification::{
    method_name: "notifications/initialized",
    params: None,
  }
  let _ = t.send_notification(notification) catch { _ => () }
  info
}

///|
/// Send a raw JSON-RPC request string and wait for the response (legacy
/// synchronous send/receive). Callers build the request body themselves.
pub async fn LegacyClient::send_raw(
  self : LegacyClient,
  request : String,
) -> String {
  self.request_mutex.acquire()
  defer self.request_mutex.release()
  let t = self.transport
  t.send(request) catch {
    e => raise @types.InternalError("Send failed: " + e.to_string())
  }
  let response = t.receive() catch {
    e => raise @types.InternalError("Receive failed: " + e.to_string())
  }
  match response {
    Some(s) => s
    None => raise @types.InternalError("Connection closed")
  }
}

///|
/// Build a JSON-RPC `ping` request string for the given id.
fn build_ping_request(id : Int32) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("ping"),
  }).stringify()
}

///|
/// Send a legacy `ping` request and wait for a response.
/// Raises `MCPError` if the response contains a JSON-RPC error.
pub async fn LegacyClient::ping(self : LegacyClient) -> Unit {
  let id = self.next_request_id()
  let request = build_ping_request(id)
  let body = self.send_raw(request)

  let json = @json.parse(body) catch {
    _ => raise @types.ParseError("Invalid ping response")
  }
  match json {
    Object(obj) =>
      match obj.get("error") {
        Some(Object(err)) => {
          let message = match err.get("message") {
            Some(String(s)) => s
            _ => "ping failed"
          }
          raise @types.InternalError(message)
        }
        _ => ()
      }
    _ => raise @types.ParseError("Ping response is not an object")
  }
}

///|
/// Create a legacy client connected over the 2025-11-25 Streamable HTTP session
/// transport and complete the `initialize` handshake. `extra_headers` are
/// applied to every request, mirroring the modern `HttpClientTransport`.
pub async fn LegacyClient::connect_http(
  url~ : String,
  name~ : String,
  version~ : String,
  auth_token~ : String = "",
  extra_headers~ : Array[(String, String)] = [],
) -> LegacyClient {
  let http_transport = LegacyHttpSessionTransport::LegacyHttpSessionTransport(
    url~,
    auth_token~,
    extra_headers~,
  )
  let client : LegacyClient = {
    client_name: name,
    client_version: version,
    transport: LegacyTransport::HttpSession(http_transport),
    request_mutex: @async.Mutex::Mutex(),
    next_id: 0,
    server_name: "unknown",
    server_version: "unknown",
  }
  errdefer http_transport.close()
  ignore(client.initialize())
  client
}

///|
/// Close the underlying transport. For the HTTP session transport this also
/// sends a best-effort DELETE to terminate the session.
pub async fn LegacyClient::close(self : LegacyClient) -> Unit {
  self.transport.close()
}
