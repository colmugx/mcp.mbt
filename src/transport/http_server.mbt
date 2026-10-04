///|
pub struct HttpTransport {
  port : Int
  endpoint_path : String
  auth : AuthConfig?
  keepalive_interval_ms : Int
  tool_schema_resolver : Ref[(String) -> Json?]
  pending_requests : @async.Queue[AuthenticatedRequest]
  pending_reply_queues : Map[String, @async.Queue[String]]
}

///|
pub fn HttpTransport::HttpTransport(
  port? : Int = 4240,
  endpoint_path? : String = "/mcp",
  keepalive_interval_ms? : Int = 15000,
) -> HttpTransport {
  guard keepalive_interval_ms > 0 else {
    abort("SSE keepalive interval must be positive")
  }
  {
    port,
    endpoint_path,
    auth: None,
    keepalive_interval_ms,
    tool_schema_resolver: Ref(fn(_) { None }),
    pending_requests: @async.Queue(kind=Unbounded),
    pending_reply_queues: {},
  }
}

///|
/// Attach a live tool-schema lookup before serving calls; MCPServer installs its registry.
pub fn HttpTransport::set_tool_schema_resolver(
  self : HttpTransport,
  resolver : (String) -> Json?,
) -> Unit {
  self.tool_schema_resolver.val = resolver
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
  { ..self, auth: Some(auth), }
}

///|
/// `@stdio.stderr` wraps one IO handle: two overlapping writes abort the
/// runtime (`guard! handle.write is Idle` in the async event loop), so
/// concurrent HttpTransport instances (or concurrent request handlers)
/// serialize their diagnostic logging through this try-lock. A busy lock
/// drops the line — logging here is best-effort, every write is already
/// `catch`-guarded.
let stderr_log_busy : Ref[Bool] = Ref(false)

///|
/// Best-effort, concurrency-safe stderr log line.
async fn log_stderr(line : String) -> Unit noraise {
  if stderr_log_busy.val {
    return
  }
  stderr_log_busy.val = true
  let _ = @stdio.stderr.write(line) catch { _ => () }
  stderr_log_busy.val = false
}

///|
pub async fn HttpTransport::start(
  self : HttpTransport,
) -> Unit raise @types.TransportError {
  let addr = "127.0.0.1:" + self.port.to_string()
  log_stderr("[HttpTransport] Binding to " + addr + self.endpoint_path + "\n")
  let server = @http.Server(@socket.Addr::parse(addr), reuse_addr=true) catch {
    e => raise @types.WriteError("Failed to create server: " + e.to_string())
  }
  log_stderr("[HttpTransport] Streamable HTTP server ready\n")
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
    // Origin validation for DNS rebinding prevention (spec
    // basic/transports/streamable-http#security-endpoint): every request to
    // the MCP endpoint is checked, with or without configured auth. An
    // explicit allowlist wins; otherwise only loopback origins pass by
    // default. Requests without an Origin header are non-browser clients
    // and are allowed.
    let allowed_origins = match self.auth {
      Some(auth) => auth.allowed_origins
      None => None
    }
    match req.headers.get("origin") {
      Some(origin) =>
        if !origin_allowed(origin, allowed_origins) {
          conn.send_response(403, "Forbidden", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write("{\"error\":\"invalid_origin\"}")
          conn.end_response()
          return
        }
      None => ()
    }
    // Auth validation (when configured)
    let principal = match self.auth {
      Some(auth) => {
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
        let authenticated = (auth.authenticate)(token)
        if authenticated is None {
          let www_auth = "Bearer resource_metadata=\"" +
            auth.resource_metadata_url +
            "\", error=\"invalid_token\""
          conn.send_response(401, "Unauthorized", extra_headers={
            "WWW-Authenticate": www_auth,
          })
          conn.end_response()
          return
        }
        authenticated
      }
      None => None
    }
    log_stderr("[HttpTransport] Request to " + req.path + "\n")
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
        let cancellation_token = @runtime.CancellationToken::new()
        let completed = Ref(false)
        defer {
          if !completed.val {
            cancellation_token.cancel()
          }
          reply_queue.close(clear=true)
        }
        try {
          self.pending_requests.put({
            message,
            reply: reply_queue,
            principal,
            cancellation_token,
          })
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
                  "Cache-Control": "no-cache",
                  "MCP-Protocol-Version": @types.ProtocolVersion,
                })
                // ServerConnection writes are buffered; without an explicit
                // flush nothing reaches the wire until end_response, which
                // for a long-lived subscriptions/listen stream never comes.
                conn.flush()
                conn.write(sse_event_line(first))
                conn.flush()
                @async.with_task_group(group => {
                  // Keepalive travels through the same queue: exactly one task owns socket writes.
                  // This detects disconnects without consuming pipelined HTTP request bytes.
                  group.spawn_bg(
                    () => {
                      while true {
                        @async.sleep(self.keepalive_interval_ms)
                        reply_queue.put(": keepalive\n\n")
                      }
                    },
                    no_wait=true,
                  )
                  while true {
                    let msg = reply_queue.get()
                    if msg == ": keepalive\n\n" {
                      conn.write(msg)
                    } else {
                      conn.write(sse_event_line(msg))
                    }
                    conn.flush()
                    if classify_jsonrpc_message(msg) is FinalResponse {
                      break
                    }
                  }
                })
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
          completed.val = true
        } catch {
          _ =>
            // A response may already be streaming. Never send a second status line after I/O failure.
            conn.close()
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
/// Checked per spec basic/transports/streamable-http#server-validation:
/// - `MCP-Protocol-Version` present, equals the server's supported version,
///   and matches body `_meta.protocolVersion` when present.
/// - `Mcp-Method` present and matches body `method` for requests.
/// - `Mcp-Name` present for tools/call|resources/read|prompts/get requests
///   and matches body `params.name` (or `params.uri` for resources/read).
/// - `Mcp-Name` and recognized `Mcp-Param-*` values decode safely and match
///   their body values; annotated non-null parameters require headers.
/// - Requests (notifications excluded) carry the required `params._meta`
///   fields `io.modelcontextprotocol/protocolVersion` (string) and
///   `io.modelcontextprotocol/clientCapabilities` (object) per basic/index
///   #_meta.
///
/// Header/value failures return `HeaderMismatch` (-32020) except for an
/// unsupported protocol version, which returns `UnsupportedProtocolVersion`
/// (-32022). A missing or ill-typed required `_meta` field returns
/// `InvalidParams` (-32602). Every error body echoes the request `id` when
/// it can be read from the body; the caller maps all of these to HTTP 400.
fn HttpTransport::validate_request_headers(
  self : HttpTransport,
  req : @http.Request,
  body : String,
  is_notif~ : Bool,
) -> Result[Unit, String] {
  ignore(self)
  let json = @json.parse(body) catch {
    _ => return Err(header_mismatch_error("malformed JSON body", body~))
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
        return Err(unsupported_protocol_version_error(h, body~))
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
                body~,
              ),
            )
          }
        None => ()
      }
    }
    None =>
      return Err(
        header_mismatch_error(
          "missing required MCP-Protocol-Version header",
          body~,
        ),
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
              body~,
            ),
          )
        }
      None =>
        return Err(
          header_mismatch_error("missing required Mcp-Method header", body~),
        )
    }
  }
  // Mcp-Name for the three name-bearing methods (requests only).
  if !is_notif {
    match body_method {
      "tools/call" | "prompts/get" =>
        match req.headers.get("mcp-name") {
          Some(h) => {
            let body_name = extract_body_string(json, "params", "name")
            match validate_name_header(h, body_name, body~) {
              Err(e) => return Err(e)
              Ok(_) => ()
            }
          }
          None =>
            return Err(
              header_mismatch_error(
                "missing required Mcp-Name header for " + body_method,
                body~,
              ),
            )
        }
      "resources/read" =>
        match req.headers.get("mcp-name") {
          Some(h) => {
            let body_uri = extract_body_string(json, "params", "uri")
            match validate_name_header(h, body_uri, body~) {
              Err(e) => return Err(e)
              Ok(_) => ()
            }
          }
          None =>
            return Err(
              header_mismatch_error(
                "missing required Mcp-Name header for resources/read",
                body~,
              ),
            )
        }
      _ => ()
    }
  }
  if !is_notif && body_method == "tools/call" {
    match extract_body_string(json, "params", "name") {
      Some(name) =>
        match (self.tool_schema_resolver.val)(name) {
          Some(schema) => {
            let arguments = match json {
              Object(fields) =>
                match fields.get("params") {
                  Some(Object(params)) =>
                    params.get("arguments").unwrap_or(Json::object({}))
                  _ => Json::object({})
                }
              _ => Json::object({})
            }
            let headers : Array[(String, String)] = []
            for name, value in req.headers {
              headers.push((name.0, value))
            }
            match validate_tool_parameter_headers(schema, arguments, headers) {
              Ok(_) => ()
              Err(reason) => return Err(header_mismatch_error(reason, body~))
            }
          }
          None => ()
        }
      None => ()
    }
  }
  // Required body `_meta` fields (requests only; notifications carry no
  // mandatory `_meta` in this revision, so they are left unconstrained).
  // Headers are valid at this point; a request whose `_meta` is missing a
  // required field (or carries it with the wrong type) is malformed and
  // gets `Invalid params` (-32602), returned as HTTP 400 by the caller.
  // `body_pv` doubles as the protocolVersion presence check: it is `None`
  // when the field is absent or not a string.
  if !is_notif {
    if body_pv is None {
      return Err(
        invalid_params_error(
          "Missing required _meta field: io.modelcontextprotocol/protocolVersion",
          body~,
        ),
      )
    }
    if !(extract_meta_field(json, "io.modelcontextprotocol/clientCapabilities")
      is Some(Object(_))) {
      return Err(
        invalid_params_error(
          "Missing required _meta field: io.modelcontextprotocol/clientCapabilities",
          body~,
        ),
      )
    }
  }
  Ok(())
}

///|
/// Validate an `Mcp-Name` header value: decode Base64 sentinels, reject
/// invalid characters in plain values, and compare with the body value.
/// `body` is the raw request body, used to echo the request `id` in error
/// responses.
fn validate_name_header(
  header_value : String,
  body_value : String?,
  body~ : String,
) -> Result[Unit, String] {
  let expected = body_value.unwrap_or("")
  let decoded = match decode_mirrored_header(header_value) {
    Ok(value) => value
    Err(reason) =>
      return Err(header_mismatch_error("Mcp-Name: " + reason, body~))
  }
  if decoded != expected {
    return Err(
      header_mismatch_error("Mcp-Name header does not match body value", body~),
    )
  }
  Ok(())
}

///|
/// Extract `_meta[key]` from a JSON-RPC message body.
fn extract_meta_field(body : Json, key : String) -> Json? {
  if body is Object(obj) {
    match obj.get("params") {
      Some(Object(params)) =>
        match params.get("_meta") {
          Some(Object(meta)) => meta.get(key)
          _ => None
        }
      _ => None
    }
  } else {
    None
  }
}

///|
/// Extract `_meta[key]` as a string from a JSON-RPC message body.
fn extract_meta_string(body : Json, key : String) -> String? {
  match extract_meta_field(body, key) {
    Some(String(s)) => Some(s)
    _ => None
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
pub async fn HttpTransport::receive_authenticated_request(
  self : HttpTransport,
) -> AuthenticatedRequest? raise @types.TransportError {
  Some(self.pending_requests.get()) catch {
    e => raise @types.ReadError(e.to_string())
  }
}

///|
/// Low-level compatibility adapter. Runtime consumers should retain the authenticated envelope.
pub async fn HttpTransport::receive_request(
  self : HttpTransport,
) -> (String, @async.Queue[String])? raise @types.TransportError {
  self
  .receive_authenticated_request()
  .map(fn(request) { (request.message, request.reply) })
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
pub fn HttpTransport::close(self : HttpTransport) -> Unit {
  ignore(self)
}
