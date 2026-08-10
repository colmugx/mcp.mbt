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
  transport : @transport.AnyTransport
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
    transport,
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
/// Perform the legacy initialize handshake: send `initialize`, parse
/// `serverInfo`/`protocolVersion` from the response, then send
/// `notifications/initialized`. Returns the server identity on success.
pub async fn LegacyClient::initialize(
  self : LegacyClient,
) -> Result[@types.ServerInfo, @types.MCPError] {
  let id = self.next_request_id()
  // Build the initialize request body for the 2025-11-25 shape.
  let caps : Map[String, Json] = Map([])
  caps.set("roots", Json::object({ "listChanged": Json::boolean(true) }))
  caps.set("sampling", Json::object({}))
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
  let json = @json.parse(response_str) catch {
    _ => return Err(@types.ParseError("Invalid initialize response"))
  }
  // Parse serverInfo.
  if json is Object(obj) {
    match obj.get("result") {
      Some(Object(result)) =>
        match result.get("serverInfo") {
          Some(Object(info)) => {
            self.server_name = match info.get("name") {
              Some(String(n)) => n
              _ => "unknown"
            }
            self.server_version = match info.get("version") {
              Some(String(v)) => v
              _ => "unknown"
            }
          }
          _ => ()
        }
      _ =>
        return Err(@types.InvalidRequest("initialize response missing result"))
    }
  } else {
    return Err(@types.ParseError("initialize response is not an object"))
  }
  // Send notifications/initialized to complete the handshake.
  let notif = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/initialized"),
  }).stringify()
  let _ = t.send(notif) catch { _ => () }
  Ok({
    name: self.server_name,
    title: None,
    version: self.server_version,
    description: None,
  })
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
