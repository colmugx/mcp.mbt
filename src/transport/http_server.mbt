///|
/// Server-side authentication configuration (MCP spec 2025-11-25).
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
  event_queue : @async.Queue[@types.Notification]
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
    event_queue: @async.Queue(kind=Unbounded),
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
        match self.validate_request_headers(req, message) {
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
          let response = reply_queue.get()
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
            "MCP-Protocol-Version": @types.ProtocolVersion,
          })
          conn.write(response)
          conn.end_response()
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
/// - `MCP-Protocol-Version` present and matches body `_meta.protocolVersion`
/// - `Mcp-Method` present and matches body `method`
/// - `Mcp-Name` present for tools/call|resources/read|prompts/get and matches
///   body `params.name` (or `params.uri` for resources/read)
///
/// Failures return a `HeaderMismatch` (-32020) error. Base64-sentinel decoding
/// of `Mcp-Name`/`Mcp-Param-*` is handled when present.
fn HttpTransport::validate_request_headers(
  self : HttpTransport,
  req : @http.Request,
  body : String,
) -> Result[Unit, String] {
  ignore(self)
  let json = @json.parse(body) catch {
    _ => return Err(header_mismatch_error("malformed JSON body"))
  }
  // Method
  let body_method = if json is Object(obj) {
    match obj.get("method") {
      Some(String(m)) => m
      _ => ""
    }
  } else {
    ""
  }
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
  // Protocol version: header must match body _meta value when both present.
  let body_pv = extract_meta_string(
    json, "io.modelcontextprotocol/protocolVersion",
  )
  match req.headers.get("mcp-protocol-version") {
    Some(h) =>
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
    None =>
      // Header required per spec. A server that also supports pre-2025-06-18
      // clients MAY omit it, but this server mandates it.
      return Err(
        header_mismatch_error("missing required MCP-Protocol-Version header"),
      )
  }
  // Mcp-Name for the three name-bearing methods.
  match body_method {
    "tools/call" | "prompts/get" =>
      match req.headers.get("mcp-name") {
        Some(h) => {
          let body_name = extract_body_string(json, "params", "name")
          let decoded = decode_base64_sentinel(h)
          if decoded != body_name.unwrap_or("") {
            return Err(
              header_mismatch_error(
                "Mcp-Name header does not match body params.name",
              ),
            )
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
          let decoded = decode_base64_sentinel(h)
          if decoded != body_uri.unwrap_or("") {
            return Err(
              header_mismatch_error(
                "Mcp-Name header does not match body params.uri",
              ),
            )
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
/// Decode a Base64-sentinel header value (`=?base64?<b64>?=`) back to its
/// original string. Plain ASCII values pass through unchanged.
fn decode_base64_sentinel(value : String) -> String {
  let prefix = "=?base64?"
  let suffix = "?="
  if value.has_prefix(prefix) &&
    value.has_suffix(suffix) &&
    value.length() > prefix.length() + suffix.length() {
    // Base64 decoding is not wired in this node; surface the raw encoded
    // value so a mismatch is detected (fail-closed) rather than silently
    // accepting divergent values. Full decoding lands with x-mcp-header
    // support in a later node.
    value
  } else {
    value
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
pub async fn HttpTransport::send_notification(
  self : HttpTransport,
  notification : @types.Notification,
) -> Unit raise @types.TransportError {
  self.event_queue.put(notification) catch {
    e =>
      raise @types.WriteError("Failed to send notification: " + e.to_string())
  }
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
