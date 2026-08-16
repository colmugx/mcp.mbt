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
/// loop. Era probing and ClientBackend dispatch in the modern client are the
/// integration layer that decides when to construct a LegacyClient; that
/// integration is tracked as a follow-up.

///|
/// Protocol version this legacy client advertises during initialize.
let legacy_protocol_version : String = "2025-11-25"

///|
pub struct LegacyClient {
  client_name : String
  client_version : String
  transport : LegacyTransport
  mut next_id : Int
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
    next_id: 0,
    server_name: "unknown",
    server_version: "unknown",
  }
}

///|
fn LegacyClient::next_request_id(self : LegacyClient) -> Int {
  self.next_id = self.next_id + 1
  self.next_id
}

///|
/// Parse the `InitializeResult` response into `ServerInfo`.
fn parse_initialize_response(
  response : String,
) -> Result[@types.ServerInfo, @types.MCPError] {
  let json = @json.parse(response) catch {
    _ => return Err(@types.ParseError("Invalid initialize response"))
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
              Ok({ name, title: None, version, description: None })
            }
            _ =>
              Ok({
                name: "unknown",
                title: None,
                version: "unknown",
                description: None,
              })
          }
        _ => Err(@types.InvalidRequest("initialize response missing result"))
      }
    _ => Err(@types.ParseError("initialize response is not an object"))
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
pub async fn LegacyClient::initialize(
  self : LegacyClient,
) -> Result[@types.ServerInfo, @types.MCPError] {
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
    e => return Err(@types.InternalError("Send failed: " + e.to_string()))
  }
  let response = t.receive() catch {
    e => return Err(@types.InternalError("Receive failed: " + e.to_string()))
  }
  let response_str = match response {
    Some(s) => s
    None =>
      return Err(@types.InternalError("Connection closed during initialize"))
  }
  let info = match parse_initialize_response(response_str) {
    Ok(i) => i
    Err(e) => return Err(e)
  }
  self.server_name = info.name
  self.server_version = info.version
  // Send notifications/initialized to complete the handshake.
  let notification = @types.Notification::{
    method_name: "notifications/initialized",
    params: None,
  }
  let _ = t.send_notification(notification) catch { _ => () }
  Ok(info)
}

///|
/// Send a raw JSON-RPC request string and wait for the response (legacy
/// synchronous send/receive). Callers build the request body themselves.
pub async fn LegacyClient::send_raw(
  self : LegacyClient,
  request : String,
) -> Result[String, @types.MCPError] {
  let t = self.transport
  t.send(request) catch {
    e => return Err(@types.InternalError("Send failed: " + e.to_string()))
  }
  let response = t.receive() catch {
    e => return Err(@types.InternalError("Receive failed: " + e.to_string()))
  }
  match response {
    Some(s) => Ok(s)
    None => Err(@types.InternalError("Connection closed"))
  }
}

///|
/// Build a JSON-RPC `ping` request string for the given id.
fn build_ping_request(id : Int) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("ping"),
  }).stringify()
}

///|
/// Send a legacy `ping` request and wait for a response.
/// Returns `Ok(())` if the response contains no JSON-RPC error.
pub async fn LegacyClient::ping(
  self : LegacyClient,
) -> Result[Unit, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_ping_request(id)
  let response = self.send_raw(request)
  match response {
    Ok(body) => {
      let json = @json.parse(body) catch {
        _ => return Err(@types.ParseError("Invalid ping response"))
      }
      match json {
        Object(obj) =>
          match obj.get("error") {
            Some(Object(err)) => {
              let message = match err.get("message") {
                Some(String(s)) => s
                _ => "ping failed"
              }
              Err(@types.InternalError(message))
            }
            _ => Ok(())
          }
        _ => Err(@types.ParseError("Ping response is not an object"))
      }
    }
    Err(e) => Err(e)
  }
}

///|
/// Create a legacy client connected over the 2025-11-25 Streamable HTTP session
/// transport and complete the `initialize` handshake.
pub async fn LegacyClient::connect_http(
  url~ : String,
  name~ : String,
  version~ : String,
  auth_token? : String = "",
) -> Result[LegacyClient, @types.MCPError] {
  let http_transport = LegacyHttpSessionTransport::LegacyHttpSessionTransport(
    url~,
    auth_token~,
  )
  let client : LegacyClient = {
    client_name: name,
    client_version: version,
    transport: LegacyTransport::HttpSession(http_transport),
    next_id: 0,
    server_name: "unknown",
    server_version: "unknown",
  }
  match client.initialize() {
    Ok(_) => Ok(client)
    Err(e) => Err(e)
  }
}

///|
/// Close the underlying transport. For the HTTP session transport this also
/// sends a best-effort DELETE to terminate the session.
pub async fn LegacyClient::close(self : LegacyClient) -> Unit {
  self.transport.close()
}
