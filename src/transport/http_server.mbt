///|
/// Server-side authentication configuration (MCP spec 2026-07-28).
/// Provides Bearer token validation, Protected Resource Metadata,
/// and Origin header validation for DNS rebinding prevention.
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
pub struct HttpTransport {
  port : Int
  endpoint_path : String
  auth : AuthConfig?
  pending_requests : @async.Queue[(String, @async.Queue[String])]
  pending_reply_queues : Map[String, @async.Queue[String]]
}

///|
pub fn HttpTransport::HttpTransport(
  port? : Int = 4240,
  endpoint_path? : String = "/mcp",
) -> HttpTransport {
  {
    port,
    endpoint_path,
    auth: None,
    pending_requests: @async.Queue(kind=Unbounded),
    pending_reply_queues: {},
  }
}

///|
fn id_key_from_json(value : Json) -> String? {
  match value {
    Number(n, ..) => Some("n:" + n.to_int().to_string())
    String(s) => Some("s:" + s)
    _ => None
  }
}

///|
fn id_key_from_message(message : String) -> String? {
  let json = @json.parse(message) catch { _ => return None }
  if json is Object(obj) {
    match obj.get("id") {
      Some(id) => id_key_from_json(id)
      None => None
    }
  } else {
    None
  }
}

///|
pub fn HttpTransport::with_auth(
  self : HttpTransport,
  auth : AuthConfig,
) -> HttpTransport {
  { ..self, auth: Some(auth) }
}

///|
pub async fn HttpTransport::start(
  self : HttpTransport,
) -> Unit raise @types.TransportError {
  let addr = "127.0.0.1:" + self.port.to_string()
  let _ = @stdio.stderr.write(
    "[HttpTransport] Binding to " + addr + self.endpoint_path + "\n",
  ) catch {
    _ => ()
  }
  let server = @http.Server(@socket.Addr::parse(addr), reuse_addr=true) catch {
    e => raise @types.WriteError("Failed to create server: " + e.to_string())
  }
  let _ = @stdio.stderr.write("[HttpTransport] Streamable HTTP server ready\n") catch {
    _ => ()
  }
  server.run_forever(async fn(req, body, conn) {
    // Protected Resource Metadata endpoint (RFC 9728)
    if req.path == "/.well-known/oauth-protected-resource" {
      match self.auth {
        Some(auth) => {
          let resource = "http://127.0.0.1:" +
            self.port.to_string() +
            self.endpoint_path
          let servers_json = auth.authorization_servers
            .map(fn(s) { "\"" + s + "\"" })
            .join(", ")
          let metadata = "{\"resource\":\"" +
            resource +
            "\",\"authorization_servers\":[" +
            servers_json +
            "]}"
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
            "Cache-Control": "max-age=3600",
          })
          conn.write(metadata)
          conn.end_response()
          return
        }
        None => {
          conn.send_response(404, "Not Found")
          conn.end_response()
          return
        }
      }
    }
    if req.path != self.endpoint_path {
      conn.send_response(404, "Not Found")
      conn.end_response()
      return
    }
    // Auth validation (when configured)
    match self.auth {
      Some(auth) => {
        // Origin validation for DNS rebinding prevention
        match auth.allowed_origins {
          Some(origins) =>
            match req.headers.get("origin") {
              Some(origin) =>
                if !origins.exists(fn(o) { o == origin }) {
                  conn.send_response(403, "Forbidden", extra_headers={
                    "Content-Type": "application/json",
                  })
                  conn.write("{\"error\":\"invalid_origin\"}")
                  conn.end_response()
                  return
                }
              None => ()
            }
          None => ()
        }
        // Token validation
        let auth_header = match req.headers.get("authorization") {
          Some(h) => h
          None => ""
        }
        if !auth_header.has_prefix("Bearer ") {
          let www_auth = "Bearer resource_metadata=\"" +
            auth.resource_metadata_url +
            "\""
          let www_auth_full = match auth.required_scopes {
            Some(scopes) => www_auth + ", scope=\"" + scopes + "\""
            None => www_auth
          }
          conn.send_response(401, "Unauthorized", extra_headers={
            "WWW-Authenticate": www_auth_full,
          })
          conn.end_response()
          return
        }
        let token = auth_header[7:].trim().to_owned()
        if !(auth.verify_token)(token) {
          let www_auth = "Bearer resource_metadata=\"" +
            auth.resource_metadata_url +
            "\", error=\"invalid_token\""
          conn.send_response(401, "Unauthorized", extra_headers={
            "WWW-Authenticate": www_auth,
          })
          conn.end_response()
          return
        }
      }
      None => ()
    }
    let _ = @stdio.stderr.write("[HttpTransport] Request to " + req.path + "\n") catch {
      _ => ()
    }
    match req.meth {
      Post => {
        let message = body.read_all().text() catch {
            _ => {
              conn.send_response(400, "Bad Request")
              conn.end_response()
              return
            }
          }
        let parsed = @json.parse(message) catch { _ => null }
        let is_notif = is_notification(parsed)
        match self.validate_request_headers(req, message, is_notif~) {
          Err(err_response) => {
            conn.send_response(400, "Bad Request", extra_headers={
              "Content-Type": "application/json",
            })
            conn.write(err_response)
            conn.end_response()
            return
          }
          Ok(_) => ()
        }
        let reply_queue = @async.Queue(kind=Blocking(1))
        try {
          self.pending_requests.put((message, reply_queue))
          if is_notif {
            // JSON-RPC notification: accept and close immediately. The server
            // handler consumes the queued notification; no reply is expected.
            conn.send_response(202, "Accepted", extra_headers={
              "MCP-Protocol-Version": @types.ProtocolVersion,
            })
            conn.end_response()
          } else {
            // JSON-RPC request: per-request response, either single JSON or
            // an SSE stream scoped to this request.
            let first = reply_queue.get()
            match classify_jsonrpc_message(first) {
              Notification => {
                // First message is a notification (e.g., subscriptions/listen
                // ack or progress). Switch to SSE mode and stream until the
                // final response arrives.
                conn.send_response(200, "OK", extra_headers={
                  "Content-Type": "text/event-stream",
                  "X-Accel-Buffering": "no",
                  "MCP-Protocol-Version": @types.ProtocolVersion,
                })
                // ServerConnection writes are buffered; without an explicit
                // flush nothing reaches the wire until end_response, which
                // for a long-lived subscriptions/listen stream never comes.
                conn.flush()
                conn.write(sse_event_line(first))
                conn.flush()
                while true {
                  let msg = reply_queue.get()
                  conn.write(sse_event_line(msg))
                  conn.flush()
                  if classify_jsonrpc_message(msg) is FinalResponse {
                    break
                  }
                }
                conn.end_response()
              }
              _ => {
                // Single JSON response. MethodNotFound (-32601) maps to HTTP 404.
                let status = if jsonrpc_error_code(first) == Some(-32601) {
                  404
                } else {
                  200
                }
                let reason = if status == 404 { "Not Found" } else { "OK" }
                conn.send_response(status, reason, extra_headers={
                  "Content-Type": "application/json",
                  "MCP-Protocol-Version": @types.ProtocolVersion,
                })
                conn.write(first)
                conn.end_response()
              }
            }
          }
        } catch {
          _ => {
            conn.send_response(500, "Internal Server Error")
            conn.end_response()
          }
        }
      }
      _ => {
        // GET and DELETE (legacy session/SSE mechanisms) are gone;
        // any non-POST method on the MCP endpoint is rejected.
        conn.send_response(405, "Method Not Allowed")
        conn.end_response()
      }
    }
  }) catch {
    e => raise @types.WriteError("Server stopped: " + e.to_string())
  }
}

///|
/// Validate the 2026-07-28 Streamable HTTP request-metadata headers against
/// the JSON-RPC body. Returns `Err(json_rpc_error_string)` (a complete
/// JSON-RPC error response body) on mismatch, `Ok(())` otherwise.
///
/// Checked per spec §B (Server Validation):
/// - `MCP-Protocol-Version` present, equals the server's supported version,
///   and matches body `_meta.protocolVersion` when present.
/// - `Mcp-Method` present and matches body `method` for requests.
/// - `Mcp-Name` present for tools/call|resources/read|prompts/get requests
///   and matches body `params.name` (or `params.uri` for resources/read).
/// - `Mcp-Name`/`Mcp-Param-*` values contain only permitted characters or
///   a valid Base64 sentinel encoding.
///
/// Failures return `HeaderMismatch` (-32020) except for an unsupported
/// protocol version, which returns `UnsupportedProtocolVersion` (-32022).
fn HttpTransport::validate_request_headers(
  self : HttpTransport,
  req : @http.Request,
  body : String,
  is_notif~ : Bool,
) -> Result[Unit, String] {
  ignore(self)
  let json = @json.parse(body) catch {
    _ => return Err(header_mismatch_error("malformed JSON body"))
  }
  let body_method = if json is Object(obj) {
    match obj.get("method") {
      Some(String(m)) => m
      _ => ""
    }
  } else {
    ""
  }
  // Protocol version: header is mandatory and must be the version this
  // server implements. It must also match the body `_meta` value when both
  // are present.
  let body_pv = extract_meta_string(
    json, "io.modelcontextprotocol/protocolVersion",
  )
  match req.headers.get("mcp-protocol-version") {
    Some(h) => {
      if h != @types.ProtocolVersion {
        return Err(unsupported_protocol_version_error(h))
      }
      match body_pv {
        Some(bpv) =>
          if h != bpv {
            return Err(
              header_mismatch_error(
                "MCP-Protocol-Version header '" +
                h +
                "' does not match body '" +
                bpv +
                "'",
              ),
            )
          }
        None => ()
      }
    }
    None =>
      return Err(
        header_mismatch_error("missing required MCP-Protocol-Version header"),
      )
  }
  // Method header is required only for requests. Notification POSTs do not
  // carry method-header requirements in this revision of the spec.
  if !is_notif {
    match req.headers.get("mcp-method") {
      Some(h) =>
        if h != body_method {
          return Err(
            header_mismatch_error(
              "Mcp-Method header '" +
              h +
              "' does not match body method '" +
              body_method +
              "'",
            ),
          )
        }
      None =>
        return Err(header_mismatch_error("missing required Mcp-Method header"))
    }
  }
  // Mcp-Name for the three name-bearing methods (requests only).
  if !is_notif {
    match body_method {
      "tools/call" | "prompts/get" =>
        match req.headers.get("mcp-name") {
          Some(h) => {
            let body_name = extract_body_string(json, "params", "name")
            match validate_name_header(h, body_name) {
              Err(e) => return Err(e)
              Ok(_) => ()
            }
          }
          None =>
            return Err(
              header_mismatch_error(
                "missing required Mcp-Name header for " + body_method,
              ),
            )
        }
      "resources/read" =>
        match req.headers.get("mcp-name") {
          Some(h) => {
            let body_uri = extract_body_string(json, "params", "uri")
            match validate_name_header(h, body_uri) {
              Err(e) => return Err(e)
              Ok(_) => ()
            }
          }
          None =>
            return Err(
              header_mismatch_error(
                "missing required Mcp-Name header for resources/read",
              ),
            )
        }
      _ => ()
    }
  }
  // Character-set check for any Mcp-Param-* headers. This server has no
  // tool-schema awareness, so it cannot compare values against body arguments;
  // it only rejects header values containing characters outside the safe set
  // (or a valid Base64 sentinel) per spec §B.
  for k, v in req.headers {
    if k.0.to_lower().has_prefix("mcp-param-") {
      match validate_header_value_characters(k.0, v) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    }
  }
  Ok(())
}

///|
/// Validate an `Mcp-Name` header value: decode Base64 sentinels, reject
/// invalid characters in plain values, and compare with the body value.
fn validate_name_header(
  header_value : String,
  body_value : String?,
) -> Result[Unit, String] {
  let expected = body_value.unwrap_or("")
  match decode_base64_sentinel(header_value) {
    Some(decoded) =>
      if decoded != expected {
        return Err(
          header_mismatch_error("Mcp-Name header does not match body value"),
        )
      }
    None => {
      if !is_valid_header_characters(header_value) {
        return Err(
          header_mismatch_error("Invalid characters in Mcp-Name header"),
        )
      }
      if header_value != expected {
        return Err(
          header_mismatch_error("Mcp-Name header does not match body value"),
        )
      }
    }
  }
  Ok(())
}

///|
/// Reject header values that contain characters outside the permitted HTTP
/// header value set unless they are encoded as a Base64 sentinel.
fn validate_header_value_characters(
  name : String,
  value : String,
) -> Result[Unit, String] {
  if looks_like_sentinel(value) {
    return Ok(())
  }
  if !is_valid_header_characters(value) {
    return Err(
      header_mismatch_error("Invalid characters in " + name + " header"),
    )
  }
  Ok(())
}

///|
/// Build a `HeaderMismatch` (-32020) JSON-RPC error response body.
fn header_mismatch_error(detail : String) -> String {
  let err = @types.HeaderMismatch(detail)
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "error": Json::object({
      "code": Json::number(err.to_error_code().to_double()),
      "message": Json::string(err.message()),
    }),
  }).stringify()
}

///|
/// Extract `_meta[key]` as a string from a JSON-RPC message body.
fn extract_meta_string(body : Json, key : String) -> String? {
  if body is Object(obj) {
    match obj.get("params") {
      Some(Object(params)) =>
        match params.get("_meta") {
          Some(Object(meta)) =>
            match meta.get(key) {
              Some(String(s)) => Some(s)
              _ => None
            }
          _ => None
        }
      _ => None
    }
  } else {
    None
  }
}

///|
/// Extract `body[parent][child]` as a string.
fn extract_body_string(body : Json, parent : String, child : String) -> String? {
  if body is Object(obj) {
    match obj.get(parent) {
      Some(Object(p)) =>
        match p.get(child) {
          Some(String(s)) => Some(s)
          _ => None
        }
      _ => None
    }
  } else {
    None
  }
}

///|
pub async fn HttpTransport::receive_request(
  self : HttpTransport,
) -> (String, @async.Queue[String])? raise @types.TransportError {
  try {
    let req = self.pending_requests.get()
    Some(req)
  } catch {
    e => raise @types.ReadError(e.to_string())
  }
}

///|
pub async fn HttpTransport::receive(
  self : HttpTransport,
) -> String? raise @types.TransportError {
  match self.receive_request() {
    Some((message, reply_queue)) => {
      match id_key_from_message(message) {
        Some(id_key) => self.pending_reply_queues.set(id_key, reply_queue)
        None => ()
      }
      Some(message)
    }
    None => None
  }
}

///|
pub async fn HttpTransport::send(
  self : HttpTransport,
  message : String,
) -> Unit raise @types.TransportError {
  let id_key = match id_key_from_message(message) {
    Some(id) => id
    None =>
      raise @types.InvalidState("Cannot route response without a JSON-RPC id")
  }
  match self.pending_reply_queues.get(id_key) {
    Some(q) => {
      self.pending_reply_queues.remove(id_key)
      q.put(message) catch {
        e => raise @types.WriteError(e.to_string())
      }
    }
    None =>
      raise @types.InvalidState(
        "No pending HTTP request for JSON-RPC id: " + id_key,
      )
  }
}

///|
/// Trait-required stub. Server→client notifications over HTTP flow through
/// `MCPServer`'s per-subscription reply handles (`subscriptions/listen`),
/// not through this transport; the legacy GET-SSE event queue is gone.
pub fn HttpTransport::send_notification(
  self : HttpTransport,
  _notification : @types.Notification,
) -> Unit {
  ignore(self)
}

///|
pub fn HttpTransport::send_event(
  self : HttpTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  ignore(event_type)
  ignore(data)
  ignore(self)
}

///|
pub fn HttpTransport::supports_streaming(_self : HttpTransport) -> Bool {
  true
}

///|
pub fn HttpTransport::close(self : HttpTransport) -> Unit {
  ignore(self)
}
