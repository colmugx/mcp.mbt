///|
struct RequestIdCounter {
  mut next_id : Int
}

///|
fn RequestIdCounter::RequestIdCounter() -> RequestIdCounter {
  { next_id: 0, }
}

///|
fn RequestIdCounter::next(self : RequestIdCounter) -> Int {
  self.next_id = self.next_id + 1
  self.next_id
}

///|
pub struct MCPClient {
  client_name : String
  client_version : String
  capabilities : @types.ClientCapabilities
  transport : @transport.AnyTransport
  id_counter : RequestIdCounter
  mut server_capabilities : @types.ServerCapabilities?
  mut server_info : @types.ServerInfo?
  notification_handlers : NotificationHandlers
  subscription_handlers : Map[String, (Json) -> Unit]
  sampling_handler : ((Json) -> Result[
    @types.CreateMessageResult,
    @types.MCPError,
  ])?
  roots_handler : (() -> Result[Array[@types.Root], @types.MCPError])?
  elicitation_handler : ((Json) -> Result[
    @types.ElicitationResult,
    @types.MCPError,
  ])?
  response_map : Map[Int, @aqueue.Queue[String]]
  mut event_loop_started : Bool
  mut legacy_mode : Bool
  mut backend : ClientBackend
}

///|
fn MCPClient::MCPClient(
  name~ : String,
  version~ : String,
  transport~ : @transport.AnyTransport,
  capabilities? : @types.ClientCapabilities = default_capabilities(),
) -> MCPClient {
  {
    client_name: name,
    client_version: version,
    capabilities,
    transport,
    id_counter: RequestIdCounter::RequestIdCounter(),
    server_capabilities: None,
    server_info: None,
    notification_handlers: NotificationHandlers::empty(),
    subscription_handlers: {},
    sampling_handler: None,
    roots_handler: None,
    elicitation_handler: None,
    response_map: {},
    event_loop_started: false,
    legacy_mode: false,
    backend: Modern,
  }
}

///|
/// Protocol era a client should assume when connecting.
pub(all) enum ProtocolEra {
  /// Probe with `server/discover` and silently fall back to the legacy
  /// 2025-11-25 client when the probe signals a legacy-era server. The
  /// default, era-unaware behavior.
  Auto
  /// Skip the probe entirely and connect directly through the legacy
  /// 2025-11-25 `initialize` handshake.
  Legacy
  /// Probe with `server/discover`, but treat any legacy-fallback signal as a
  /// connection error instead of silently downgrading.
  Modern
} derive(Eq)

///|
/// Error returned when `era=Modern` receives a legacy-fallback signal from
/// the probe. Wraps the original probe failure so callers can still see why
/// the server was classified as legacy-era.
fn modern_forbids_fallback_error(cause : @types.MCPError) -> @types.MCPError {
  @types.InvalidRequest(
    "era=Modern forbids legacy fallback (connect with era=Legacy for a 2025-11-25 server); probe failure: " +
    cause.message(),
  )
}

///|
/// Connect to a remote MCP server over HTTP.
///
/// `era` constrains how the protocol era is negotiated:
///
/// | era    | `server/discover` probe | legacy fallback |
/// |--------|-------------------------|-----------------|
/// | Auto   | yes (default)           | allowed         |
/// | Legacy | skipped                 | direct connect  |
/// | Modern | yes                     | forbidden (Err) |
///
/// `extra_headers` are appended to every request this transport issues, after
/// the built-in headers. Same-name entries override the built-ins (including
/// the spec-mandated `MCP-Protocol-Version`/`Mcp-Method`/`Mcp-Name` and the
/// `auth_token`-derived `Authorization` — extra wins), so pass reserved
/// headers only deliberately. The same set is applied on the legacy-era
/// fallback path, so header-gated servers (bearer, routing, session-context)
/// see identical headers on both protocol eras.
pub async fn MCPClient::connect_http(
  url~ : String,
  name~ : String,
  version~ : String,
  auth_token? : String = "",
  extra_headers? : Array[(String, String)] = [],
  era? : ProtocolEra = Auto,
) -> Result[MCPClient, @types.MCPError] {
  if era is Legacy {
    return connect_http_legacy(
      url~,
      name~,
      version~,
      auth_token~,
      extra_headers~,
    )
  }
  let transport = @transport.AnyTransport::HttpClient(
    @transport.HttpClientTransport::HttpClientTransport(
      url,
      auth_token~,
      extra_headers~,
    ),
  )
  let client = MCPClient::MCPClient(name~, version~, transport~)
  let meta = client.request_meta()
  let probe = send_discover_probe(transport, meta)
  match probe {
    Ok(caps) => {
      client.server_capabilities = Some(caps)
      Ok(client)
    }
    Err(e) =>
      match classify_probe_error(e) {
        ModernError(modern_err) =>
          // -32022 with supported 2026-07-28: the server is modern but rejected
          // this specific request, so retry once before giving up.
          if supported_contains(modern_err, @types.ProtocolVersion) {
            match send_discover_probe(transport, meta) {
              Ok(caps) => {
                client.server_capabilities = Some(caps)
                Ok(client)
              }
              Err(e2) =>
                match classify_probe_error(e2) {
                  ModernError(m2) => {
                    transport.close()
                    Err(m2)
                  }
                  Fatal => {
                    transport.close()
                    Err(e2)
                  }
                  FallbackLegacy => {
                    transport.close()
                    if era is Modern {
                      Err(modern_forbids_fallback_error(e2))
                    } else {
                      connect_http_legacy(
                        url~,
                        name~,
                        version~,
                        auth_token~,
                        extra_headers~,
                      )
                    }
                  }
                }
            }
          } else {
            transport.close()
            Err(modern_err)
          }
        Fatal => {
          transport.close()
          Err(e)
        }
        FallbackLegacy => {
          transport.close()
          if era is Modern {
            Err(modern_forbids_fallback_error(e))
          } else {
            connect_http_legacy(
              url~,
              name~,
              version~,
              auth_token~,
              extra_headers~,
            )
          }
        }
      }
  }
}

///|
fn supported_contains(err : @types.MCPError, version : String) -> Bool {
  match err {
    @types.UnsupportedProtocolVersion(_, supported~, ..) =>
      supported.contains(version)
    _ => false
  }
}

///|
async fn connect_http_legacy(
  url~ : String,
  name~ : String,
  version~ : String,
  auth_token? : String = "",
  extra_headers? : Array[(String, String)] = [],
) -> Result[MCPClient, @types.MCPError] {
  match
    @legacy.LegacyClient::connect_http(
      url~,
      name~,
      version~,
      auth_token~,
      extra_headers~,
    ) {
    Ok(legacy) => {
      let dummy = @transport.AnyTransport::Stdio(
        @transport.StdioTransport::StdioTransport(),
      )
      let client = MCPClient::MCPClient(name~, version~, transport=dummy)
      client.backend = Legacy(legacy)
      client.legacy_mode = true
      Ok(client)
    }
    Err(e) => Err(e)
  }
}

///|
/// Connect to a local MCP server by spawning it as a child process.
///
/// `era` constrains era negotiation exactly like `connect_http`:
///
/// | era    | `server/discover` probe | legacy fallback |
/// |--------|-------------------------|-----------------|
/// | Auto   | yes (default)           | allowed         |
/// | Legacy | skipped                 | direct connect  |
/// | Modern | yes                     | forbidden (Err) |
pub async fn MCPClient::connect_stdio(
  cmd~ : String,
  args? : Array[String] = [],
  name~ : String,
  version~ : String,
  extra_env? : Map[String, String] = {},
  group~ : @async.TaskGroup[Unit],
  era? : ProtocolEra = Auto,
) -> Result[MCPClient, @types.MCPError] {
  let stdio = @transport.StdioClientTransport::StdioClientTransport(
    cmd~,
    args~,
    extra_env~,
  )
  stdio.start(group) catch {
    e =>
      return Err(@types.InternalError("Stdio start failed: " + e.to_string()))
  }
  let transport = @transport.AnyTransport::StdioClient(stdio)
  if era is Legacy {
    return connect_stdio_legacy(name~, version~, transport~)
  }
  let client = MCPClient::MCPClient(name~, version~, transport~)
  let meta = client.request_meta()
  let probe : Result[@types.ServerCapabilities, @types.MCPError]? = Some(
    @async.with_timeout(3000, async fn() {
      send_discover_probe(transport, meta)
    }),
  ) catch {
    _ => None
  }
  match probe {
    None => {
      // Probe timeout: an era signal that the server may be legacy.
      let cause = @types.TransportError(@types.Timeout)
      if era is Modern {
        transport.close()
        Err(modern_forbids_fallback_error(cause))
      } else {
        connect_stdio_legacy(name~, version~, transport~)
      }
    }
    Some(Ok(caps)) => {
      client.server_capabilities = Some(caps)
      Ok(client)
    }
    Some(Err(e)) =>
      match classify_probe_error(e) {
        ModernError(modern_err) => {
          transport.close()
          Err(modern_err)
        }
        Fatal => {
          transport.close()
          Err(e)
        }
        FallbackLegacy =>
          if era is Modern {
            transport.close()
            Err(modern_forbids_fallback_error(e))
          } else {
            connect_stdio_legacy(name~, version~, transport~)
          }
      }
  }
}

///|
async fn connect_stdio_legacy(
  name~ : String,
  version~ : String,
  transport~ : @transport.AnyTransport,
) -> Result[MCPClient, @types.MCPError] {
  let legacy = @legacy.LegacyClient::LegacyClient(name~, version~, transport~)
  match legacy.initialize() {
    Ok(_) => {
      let dummy = @transport.AnyTransport::Stdio(
        @transport.StdioTransport::StdioTransport(),
      )
      let client = MCPClient::MCPClient(name~, version~, transport=dummy)
      client.backend = Legacy(legacy)
      client.legacy_mode = true
      Ok(client)
    }
    Err(e) => {
      transport.close()
      Err(e)
    }
  }
}

///|
fn default_capabilities() -> @types.ClientCapabilities {
  {
    roots: Some({ list_changed: true, }),
    sampling: Some(@types.SamplingCapabilities::{ }),
    elicitation: Some({ form: true, }),
    extensions: None,
  }
}

///|
pub fn MCPClient::next_request_id(self : MCPClient) -> Int {
  self.id_counter.next()
}

///|
/// Build the `_meta` object this client attaches to every modern request.
fn MCPClient::request_meta(
  self : MCPClient,
  log_level? : String? = None,
) -> Json {
  build_request_meta(
    self.client_name,
    self.client_version,
    self.capabilities,
    log_level~,
  )
}

///|
async fn MCPClient::send_request(
  self : MCPClient,
  request : String,
) -> Result[String, @types.MCPError] {
  if self.event_loop_started {
    // Event loop mode: register pending, send, wait on queue
    let id = extract_request_id(request)
    let queue : @aqueue.Queue[String] = @aqueue.Queue(
      kind=@aqueue.Kind::Unbounded,
    )
    self.response_map[id] = queue
    let t = self.transport
    t.send(request) catch {
      e => {
        self.response_map.remove(id)
        return Err(@types.InternalError("Send failed: " + e.to_string()))
      }
    }
    let response = queue.get() catch {
      e => {
        self.response_map.remove(id)
        if @async.is_being_cancelled() {
          self.notify_cancelled_best_effort(id.to_string())
          raise e
        }
        return Err(@types.InternalError("Response timeout"))
      }
    }
    self.maybe_store_server_info(response)
    Ok(response)
  } else {
    // Legacy mode: direct send/receive
    let id = extract_request_id(request)
    let t = self.transport
    t.send(request) catch {
      e => return Err(@types.InternalError("Send failed: " + e.to_string()))
    }
    let response = t.receive() catch {
      e => {
        if @async.is_being_cancelled() {
          self.notify_cancelled_best_effort(id.to_string())
          raise e
        }
        return Err(@types.InternalError("Receive failed: " + e.to_string()))
      }
    }
    match response {
      Some(msg) => {
        self.maybe_store_server_info(msg)
        Ok(msg)
      }
      None => Err(@types.InternalError("Connection closed"))
    }
  }
}

///|
/// Best-effort `notifications/cancelled` when task cancellation aborts an
/// in-flight request: `send_request` calls this right before re-raising the
/// cancellation. Mirrors `cancel_request` transport gating (stdio client
/// transports only; HTTP cancels by closing the SSE stream). The write is
/// shielded with `protect_from_cancel` so the level-triggered cancellation
/// cannot kill it mid-write, and any send failure is swallowed — the caller
/// is already unwinding on cancellation.
async fn MCPClient::notify_cancelled_best_effort(
  self : MCPClient,
  request_id : String,
) -> Unit {
  match self.transport {
    @transport.AnyTransport::StdioClient(_) => {
      let notif = @types.cancelled_notification(
        request_id,
        reason="client aborted",
      )
      let t = self.transport
      @async.protect_from_cancel(() => {
        t.send_notification(notif) catch {
          _ => ()
        }
      })
    }
    _ => ()
  }
}

///|
/// Send a request through a legacy backend and parse the JSON-RPC result with
/// `parse`. Legacy requests never use MRTR: input requests are a 2026-07-28
/// mechanism, and legacy servers rely on server-initiated requests instead.
async fn[T] legacy_send_and_parse(
  legacy : @legacy.LegacyClient,
  request : String,
  parse : (Json) -> Result[T, @types.MCPError],
) -> Result[T, @types.MCPError] {
  match legacy.send_raw(request) {
    Err(e) => Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => Err(e)
        Ok(result_json) => parse(result_json)
      }
  }
}

///|
/// Store `serverInfo` from a JSON-RPC response's `result._meta` if present.
/// Per migration 2.4 of the 2026-07-28 spec, server identity may ride on any
/// response, so this is called for every successful response.
fn MCPClient::maybe_store_server_info(
  self : MCPClient,
  response_str : String,
) -> Unit {
  let json = @json.parse(response_str) catch { _ => return }
  if json is Object(obj) {
    match obj.get("result") {
      Some(result_json) => {
        let info = parse_server_info_from_result(result_json)
        match info {
          Some(i) => self.server_info = Some(i)
          None => ()
        }
      }
      None => ()
    }
  }
}

///|
/// Send a request and transparently handle MRTR (Multi Round-Trip Requests).
///
/// If the server returns `resultType: "input_required"`, this fulfills the
/// requested inputs via the client's sampling/roots/elicitation handlers and
/// retries the original request with `inputResponses` + the echoed
/// `requestState`, using a new JSON-RPC id. Repeats until a `complete` result
/// (or an error) is returned. A missing `resultType` is treated as `complete`
/// per spec (back-compat with older servers); an unrecognized non-empty
/// `resultType` surfaces as an InvalidParams error.
///
/// `max_rounds` bounds the retry count to prevent infinite loops if the server
/// keeps requesting input.
async fn MCPClient::send_with_mrtr(
  self : MCPClient,
  request : String,
  max_rounds? : Int = 8,
) -> Result[String, @types.MCPError] {
  let mut current_request = request
  let mut rounds = 0
  while rounds < max_rounds {
    rounds = rounds + 1
    match self.send_request(current_request) {
      Err(e) => return Err(e)
      Ok(response) =>
        match self.check_input_required(response) {
          Err(e) => return Err(e)
          Ok(None) => return Ok(response)
          Ok(Some(input_req)) =>
            match self.fulfill_input_requests(input_req.input_requests) {
              Err(e) => return Err(e)
              Ok(responses) => {
                // Build the retry: original params + inputResponses + requestState, new id.
                let new_id = self.next_request_id()
                current_request = build_retry_request(
                  current_request,
                  new_id,
                  responses,
                  input_req.request_state,
                )
              }
            }
        }
    }
  }
  Err(@types.InternalError("MRTR exceeded max rounds"))
}

///|
/// Classify a response for the MRTR loop:
/// * `Ok(None)` — a `complete` result (a missing `resultType` also means
///   `complete`, for back-compat with pre-MRTR servers);
/// * `Ok(Some(info))` — an `input_required` result with the extracted
///   `inputRequests` map and `requestState`;
/// * `Err(InvalidParams)` — a non-empty `resultType` this SDK cannot
///   recognize, which MUST be treated as invalid per the 2026-07-28 spec.
priv struct InputRequiredInfo {
  input_requests : Map[String, (String, Json)]
  request_state : String?
}

///|
fn MCPClient::check_input_required(
  self : MCPClient,
  response : String,
) -> Result[InputRequiredInfo?, @types.MCPError] {
  ignore(self)
  let json = @json.parse(response) catch { _ => return Ok(None) }
  let result = match json {
    Object(obj) =>
      match obj.get("result") {
        Some(Object(r)) => r
        _ => return Ok(None) // no result object (e.g. an error response)
      }
    _ => return Ok(None)
  }
  match result.get("resultType") {
    None => return Ok(None) // absent => "complete"
    Some(String("complete")) => return Ok(None)
    Some(String("input_required")) => ()
    Some(String(other)) =>
      return Err(
        @types.InvalidParams("Unrecognized resultType: '" + other + "'"),
      )
    Some(_) => return Err(@types.InvalidParams("resultType must be a string"))
  }
  let reqs : Map[String, (String, Json)] = Default::default()
  match result.get("inputRequests") {
    Some(Object(map)) =>
      map.each(fn(key, val) {
        if val is Object(entry) {
          let method_name = match entry.get("method") {
            Some(String(m)) => m
            _ => ""
          }
          let params = entry.get("params").unwrap_or(Json::null())
          reqs.set(key, (method_name, params))
        }
      })
    _ => ()
  }
  let request_state = match result.get("requestState") {
    Some(String(s)) => Some(s)
    _ => None
  }
  Ok(Some({ input_requests: reqs, request_state, }))
}

///|
/// Fulfill each input request by dispatching to the matching client handler.
/// Returns a map of key → response JSON (the `inputResponses` field).
fn MCPClient::fulfill_input_requests(
  self : MCPClient,
  input_requests : Map[String, (String, Json)],
) -> Result[Map[String, Json], @types.MCPError] {
  let responses : Map[String, Json] = Default::default()
  let mut error : @types.MCPError? = None
  input_requests.each(fn(key, entry) {
    if error is Some(_) {
      return
    }
    let (method_name, params) = entry
    match method_name {
      "elicitation/create" =>
        match self.elicitation_handler {
          Some(handler) =>
            match handler(params) {
              Ok(r) => responses.set(key, elicitation_result_to_json(r))
              Err(e) => error = Some(e)
            }
          None =>
            error = Some(
              @types.MissingRequiredClientCapability(
                "no elicitation handler registered",
                required=["elicitation"],
              ),
            )
        }
      "sampling/createMessage" =>
        match self.sampling_handler {
          Some(handler) =>
            match handler(params) {
              Ok(r) => responses.set(key, sampling_result_to_json(r))
              Err(e) => error = Some(e)
            }
          None =>
            error = Some(
              @types.MissingRequiredClientCapability(
                "no sampling handler registered",
                required=["sampling"],
              ),
            )
        }
      "roots/list" =>
        match self.roots_handler {
          Some(handler) =>
            match handler() {
              Ok(roots) => responses.set(key, roots_to_json(roots))
              Err(e) => error = Some(e)
            }
          None =>
            error = Some(
              @types.MissingRequiredClientCapability(
                "no roots handler registered",
                required=["roots"],
              ),
            )
        }
      _ =>
        error = Some(
          @types.MethodNotFound("Unknown input request method: " + method_name),
        )
    }
  })
  match error {
    Some(e) => Err(e)
    None => Ok(responses)
  }
}

///|
/// Build a retry request: take the original request's params, attach
/// `inputResponses` and `requestState`, and assign a new JSON-RPC id.
fn build_retry_request(
  original : String,
  new_id : Int,
  responses : Map[String, Json],
  request_state : String?,
) -> String {
  let orig = @json.parse(original) catch { _ => return original }
  if !(orig is Object(_)) {
    return original
  }
  if orig is Object(obj) {
    let params = match obj.get("params") {
      Some(Object(p)) => p
      _ => {
        let p : Map[String, Json] = Map([])
        obj.set("params", Json::object(p))
        p
      }
    }
    params.set("inputResponses", Json::object(responses))
    match request_state {
      Some(rs) => params.set("requestState", Json::string(rs))
      None => ()
    }
    obj.set("id", Json::number(new_id.to_double()))
    orig.stringify()
  } else {
    original
  }
}

///|
fn elicitation_result_to_json(r : @types.ElicitationResult) -> Json {
  let map : Map[String, Json] = Default::default()
  map.set("action", Json::string(r.action))
  match r.content {
    Some(c) => map.set("content", c)
    None => ()
  }
  Json::object(map)
}

///|
fn sampling_result_to_json(r : @types.CreateMessageResult) -> Json {
  let map : Map[String, Json] = Default::default()
  map.set("role", Json::string(r.role))
  map.set("model", Json::string(r.model))
  // content is a ContentItem; serialize via its to_json if available, else stringify
  map.set("content", serialize_content_item(r.content))
  match r.stop_reason {
    Some(s) => map.set("stopReason", Json::string(s))
    None => ()
  }
  Json::object(map)
}

///|
fn roots_to_json(roots : Array[@types.Root]) -> Json {
  let arr = roots.map(fn(r) {
    let map : Map[String, Json] = Default::default()
    map.set("uri", Json::string(r.uri))
    match r.name {
      Some(n) => map.set("name", Json::string(n))
      None => ()
    }
    Json::object(map)
  })
  Json::object({ "roots": Json::array(arr) })
}

///|
fn extract_request_id(request : String) -> Int {
  let json = @json.parse(request) catch { _ => return 0 }
  match json {
    Object(obj) =>
      match obj.get("id") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
    _ => 0
  }
}

///|
/// Cancel an in-flight request. Per the 2026-07-28 spec
/// (transports/streamable-http), the core protocol defines no
/// client→server notification on Streamable HTTP: cancellation there is
/// signalled by closing the SSE response stream. So only stdio client
/// transports send `notifications/cancelled`; HTTP and other transports
/// return a clear error instead (same style as `cancel_listen`).
pub async fn MCPClient::cancel_request(
  self : MCPClient,
  request_id : String,
  reason? : String,
) -> Result[Unit, @types.MCPError] {
  if self.backend is Legacy(_) {
    return Err(
      @types.MethodNotFound(
        "request cancellation is not supported by the legacy fallback client",
      ),
    )
  }
  match self.transport {
    @transport.AnyTransport::StdioClient(_) => {
      let notif = match reason {
        Some(r) => @types.cancelled_notification(request_id, reason=r)
        None => @types.cancelled_notification(request_id)
      }
      let t = self.transport
      t.send_notification(notif) catch {
        e =>
          return Err(
            @types.InternalError(
              "Failed to send cancellation: " + e.to_string(),
            ),
          )
      }
      Ok(())
    }
    @transport.AnyTransport::HttpClient(_) =>
      Err(
        @types.InternalError(
          "HTTP cancellation is not yet supported; cancel by closing the SSE response stream",
        ),
      )
    _ =>
      Err(
        @types.InternalError(
          "request cancellation is not supported for this transport",
        ),
      )
  }
}

///|
/// Query the server's supported versions, capabilities, and identity via
/// `server/discover` (required by the 2026-07-28 spec). Stores the results
/// in `server_capabilities` and `server_info` for later use. Optional for
/// clients per spec, but recommended — and the primary era probe for legacy
/// fallback.
pub async fn MCPClient::discover(
  self : MCPClient,
) -> Result[@types.ServerCapabilities, @types.MCPError] {
  match self.backend {
    Legacy(legacy) => {
      let id = self.next_request_id()
      let request = apply_legacy_meta_to_request(
        build_discover_request(id, self.request_meta()),
        build_legacy_meta(),
      )
      match legacy.send_raw(request) {
        Err(e) => Err(e)
        Ok(response_str) =>
          match parse_jsonrpc_response(response_str) {
            Err(e) => Err(e)
            Ok(result_json) => {
              let caps = parse_discover_capabilities(result_json)
              self.server_capabilities = Some(caps)
              self.server_info = parse_server_info_from_result(result_json)
              Ok(caps)
            }
          }
      }
    }
    Modern => {
      let id = self.next_request_id()
      let request = build_discover_request(id, self.request_meta())
      match self.send_request(request) {
        Err(e) => return Err(e)
        Ok(response_str) =>
          match parse_jsonrpc_response(response_str) {
            Err(e) => return Err(e)
            Ok(result_json) => {
              let caps = parse_discover_capabilities(result_json)
              self.server_capabilities = Some(caps)
              self.server_info = parse_server_info_from_result(result_json)
              Ok(caps)
            }
          }
      }
    }
  }
}

///|
pub async fn MCPClient::list_tools(
  self : MCPClient,
  cursor? : String = "",
) -> Result[ListToolsResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_tools_list_request(id, self.request_meta(), cursor~)
  match self.backend {
    Legacy(legacy) => {
      let legacy_request = apply_legacy_meta_to_request(
        request,
        build_legacy_meta(),
      )
      legacy_send_and_parse(legacy, legacy_request, parse_tools_list)
    }
    Modern =>
      match self.send_request(request) {
        Err(e) => return Err(e)
        Ok(response_str) =>
          match parse_jsonrpc_response(response_str) {
            Err(e) => return Err(e)
            Ok(result_json) => {
              let result = parse_tools_list(result_json)
              match result {
                Err(e) => Err(e)
                Ok(list_result) => {
                  let valid_tools : Array[@types.ToolDefinition] = []
                  let header_schemas : Map[
                    String,
                    Array[(Array[String], String)],
                  ] = Default::default()
                  for tool in list_result.tools {
                    match validate_tool_header_schema(tool.input_schema) {
                      Valid(entries) => {
                        valid_tools.push(tool)
                        if entries.length() > 0 {
                          header_schemas.set(tool.name, entries)
                        }
                      }
                      Invalid(reason) =>
                        println(
                          "WARN: rejecting tool '" +
                          tool.name +
                          "' due to invalid x-mcp-header schema: " +
                          reason,
                        )
                    }
                  }
                  // Push validated schemas to the HTTP transport so tools/call can
                  // mirror parameters as Mcp-Param-* headers.
                  match self.transport {
                    @transport.AnyTransport::HttpClient(t) =>
                      t.set_tool_header_schemas(header_schemas)
                    _ => ()
                  }
                  Ok({
                    tools: valid_tools,
                    next_cursor: list_result.next_cursor,
                  })
                }
              }
            }
          }
      }
  }
}

///|
pub async fn MCPClient::call_tool(
  self : MCPClient,
  name : String,
  arguments? : String = "{}",
) -> Result[CallToolResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_tools_call_request(
    id,
    name,
    self.request_meta(),
    arguments~,
  )
  // Legacy backends: plain send/receive, no MRTR (a 2026-07-28 mechanism).
  if self.backend is Legacy(legacy) {
    return legacy_send_and_parse(
      legacy,
      apply_legacy_meta_to_request(request, build_legacy_meta()),
      parse_call_tool,
    )
  }
  match self.send_with_mrtr(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_call_tool(result_json)
      }
  }
}

///|
pub async fn MCPClient::list_resources(
  self : MCPClient,
  cursor? : String = "",
) -> Result[ListResourcesResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_resources_list_request(id, self.request_meta(), cursor~)
  if self.backend is Legacy(legacy) {
    return legacy_send_and_parse(
      legacy,
      apply_legacy_meta_to_request(request, build_legacy_meta()),
      parse_list_resources,
    )
  }
  match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_list_resources(result_json)
      }
  }
}

///|
pub async fn MCPClient::read_resource(
  self : MCPClient,
  uri : String,
) -> Result[ReadResourceResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_resources_read_request(id, uri, self.request_meta())
  if self.backend is Legacy(legacy) {
    return legacy_send_and_parse(
      legacy,
      apply_legacy_meta_to_request(request, build_legacy_meta()),
      parse_read_resource,
    )
  }
  match self.send_with_mrtr(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_read_resource(result_json)
      }
  }
}

///|
pub async fn MCPClient::list_prompts(
  self : MCPClient,
  cursor? : String = "",
) -> Result[ListPromptsResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_prompts_list_request(id, self.request_meta(), cursor~)
  if self.backend is Legacy(legacy) {
    return legacy_send_and_parse(
      legacy,
      apply_legacy_meta_to_request(request, build_legacy_meta()),
      parse_list_prompts,
    )
  }
  match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_list_prompts(result_json)
      }
  }
}

///|
pub async fn MCPClient::get_prompt(
  self : MCPClient,
  name : String,
  arguments? : String = "{}",
) -> Result[@types.GetPromptResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_prompts_get_request(
    id,
    name,
    self.request_meta(),
    arguments~,
  )
  if self.backend is Legacy(legacy) {
    return legacy_send_and_parse(
      legacy,
      apply_legacy_meta_to_request(request, build_legacy_meta()),
      parse_get_prompt,
    )
  }
  match self.send_with_mrtr(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_get_prompt(result_json)
      }
  }
}

///|
pub async fn MCPClient::list_resource_templates(
  self : MCPClient,
  cursor? : String = "",
) -> Result[ListResourceTemplatesResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_resources_templates_list_request(
    id,
    self.request_meta(),
    cursor~,
  )
  if self.backend is Legacy(legacy) {
    return legacy_send_and_parse(
      legacy,
      apply_legacy_meta_to_request(request, build_legacy_meta()),
      parse_list_resource_templates,
    )
  }
  match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_list_resource_templates(result_json)
      }
  }
}

///|
pub async fn MCPClient::complete(
  self : MCPClient,
  ref_type~ : String,
  ref_name~ : String,
  argument_name~ : String,
  argument_value~ : String,
) -> Result[CompletionResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_completion_complete_request(
    id,
    self.request_meta(),
    ref_type~,
    ref_name~,
    argument_name~,
    argument_value~,
  )
  if self.backend is Legacy(legacy) {
    return legacy_send_and_parse(
      legacy,
      apply_legacy_meta_to_request(request, build_legacy_meta()),
      parse_completion_result,
    )
  }
  match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_completion_result(result_json)
      }
  }
}

///|
pub async fn MCPClient::close(self : MCPClient) -> Unit {
  match self.backend {
    Legacy(legacy) => legacy.close()
    Modern => self.transport.close()
  }
}

/// === Bidirectional event loop ===

///|
pub fn MCPClient::on_sampling(
  self : MCPClient,
  handler : (Json) -> Result[@types.CreateMessageResult, @types.MCPError],
) -> MCPClient {
  { ..self, sampling_handler: Some(handler), }
}

///|
pub fn MCPClient::on_roots(
  self : MCPClient,
  handler : () -> Result[Array[@types.Root], @types.MCPError],
) -> MCPClient {
  { ..self, roots_handler: Some(handler), }
}

///|
pub fn MCPClient::on_elicitation(
  self : MCPClient,
  handler : (Json) -> Result[@types.ElicitationResult, @types.MCPError],
) -> MCPClient {
  { ..self, elicitation_handler: Some(handler), }
}

///|
pub fn MCPClient::on_notification(
  self : MCPClient,
  handlers : NotificationHandlers,
) -> MCPClient {
  { ..self, notification_handlers: handlers, }
}

///|
/// Enable or disable legacy mode. When enabled, the event loop accepts
/// server-initiated requests (2025-11-25 behavior); when disabled (the default),
/// such requests are rejected with `-32601` per the 2026-07-28 spec.
pub fn MCPClient::set_legacy_mode(
  self : MCPClient,
  enabled : Bool,
) -> MCPClient {
  self.legacy_mode = enabled
  self
}

///|
/// Start a `subscriptions/listen` request. Returns the subscription id string
/// on success. The caller must already have started the event loop via `run`;
/// otherwise a clear error is returned. Notifications carrying the subscription
/// id in `params._meta` are routed to `handler` until the server closes the
/// subscription (the final JSON-RPC response causes a background cleanup task
/// to unregister the handler).
pub fn MCPClient::listen(
  self : MCPClient,
  filter? : ListenFilter = ListenFilter::default(),
  handler~ : (Json) -> Unit,
  group~ : @async.TaskGroup[Unit],
) -> Result[String, @types.MCPError] {
  if self.backend is Legacy(_) {
    return Err(
      @types.MethodNotFound(
        "subscriptions/listen is not supported by legacy MCP servers",
      ),
    )
  }
  if !self.event_loop_started {
    return Err(
      @types.InvalidRequest(
        "event loop not started; call run(...) before listen(...)",
      ),
    )
  }
  let id = self.next_request_id()
  let id_str = id.to_string()
  let request = build_subscriptions_listen_request(
    id,
    self.request_meta(),
    filter,
  )
  self.subscription_handlers[id_str] = handler
  group.spawn_bg(async fn() {
    let _ = self.send_request(request)
    self.subscription_handlers.remove(id_str)
  })
  Ok(id_str)
}

///|
/// Cancel a running `subscriptions/listen` subscription. For stdio transports
/// this sends a `notifications/cancelled` notification. HTTP transports do not
/// currently support per-stream cancellation in this SDK, so this returns an
/// error explaining that limitation.
pub async fn MCPClient::cancel_listen(
  self : MCPClient,
  subscription_id : String,
) -> Result[Unit, @types.MCPError] {
  match self.transport {
    @transport.AnyTransport::StdioClient(_) =>
      self.cancel_request(
        subscription_id,
        reason="client cancelled listen subscription",
      )
    @transport.AnyTransport::HttpClient(_) =>
      Err(
        @types.InternalError(
          "HTTP listen cancellation is not yet supported; cancel by closing the SSE stream (TODO)",
        ),
      )
    _ =>
      Err(
        @types.InternalError(
          "listen cancellation not supported for this transport",
        ),
      )
  }
}

///|
pub async fn MCPClient::run(
  self : MCPClient,
  group : @async.TaskGroup[Unit],
) -> Unit {
  // Legacy backends use a direct request/response loop; the modern event loop
  // is not started for them.
  if self.backend is Legacy(_) {
    return
  }
  // Stateless 2026-07-28: no initialize handshake before the event loop.
  self.event_loop_started = true
  while true {
    let msg_opt = self.transport.receive() catch { _ => None }
    match msg_opt {
      None => {
        self.transport.close()
        break
      }
      Some(message) => {
        let json = @json.parse(message) catch { _ => continue }
        match json {
          Object(obj) =>
            if obj.get("method") is Some(_) && obj.get("id") is Some(_) {
              // Stateless 2026-07-28: server-initiated requests are removed.
              // Legacy mode still accepts them for interop with 2025-11-25 servers.
              if self.legacy_mode {
                self.handle_server_request(obj, group)
              } else {
                let id_json = match obj.get("id") {
                  Some(Number(n, ..)) => Json::number(n)
                  Some(String(s)) => Json::string(s)
                  _ => Json::null()
                }
                let response = jsonrpc_error_str(
                  id_json, -32601, "method not found: server-initiated requests were removed in MCP 2026-07-28, use MRTR inputRequests",
                )
                let transport = self.transport
                group.spawn_bg(() => transport.send(response) catch { _ => () })
              }
            } else if obj.get("method") is Some(_) {
              let notif : @types.Notification = {
                method_name: match obj.get("method") {
                  Some(String(m)) => m
                  _ => continue
                },
                params: obj.get("params"),
              }
              match extract_subscription_id(notif.params) {
                Some(sub_id) =>
                  match self.subscription_handlers.get(sub_id) {
                    Some(handler) =>
                      handler(notif.params.unwrap_or(Json::null()))
                    None =>
                      handle_server_notification(
                        self.notification_handlers,
                        notif,
                      )
                  }
                None =>
                  handle_server_notification(self.notification_handlers, notif)
              }
            } else if obj.get("id") is Some(_) {
              self.dispatch_response(message, obj)
            } else {
              ()
            }
          _ => ()
        }
      }
    }
  }
}

///|
fn MCPClient::dispatch_response(
  self : MCPClient,
  raw_message : String,
  obj : Map[String, Json],
) -> Unit {
  let id = match obj.get("id") {
    Some(Number(n, ..)) => n.to_int()
    _ => return
  }
  match self.response_map.get(id) {
    Some(queue) => {
      try {
        let _ = queue.try_put(raw_message)
      } catch {
        _ => ()
      }
      self.response_map.remove(id)
    }
    None => ()
  }
}

///|
fn MCPClient::handle_server_request(
  self : MCPClient,
  obj : Map[String, Json],
  group : @async.TaskGroup[Unit],
) -> Unit {
  let method_name = match obj.get("method") {
    Some(String(m)) => m
    _ => return
  }
  let id = match obj.get("id") {
    Some(Number(n, ..)) => @types.RequestId::Int(n.to_int())
    Some(String(s)) => @types.RequestId::Str(s)
    _ => return
  }
  let params = obj.get("params").unwrap_or(Json::null())
  let transport = self.transport
  let sampling_h = self.sampling_handler
  let roots_h = self.roots_handler
  let elicitation_h = self.elicitation_handler
  group.spawn_bg(() => {
    let id_json = request_id_to_json(id)
    let response : String = match method_name {
      "sampling/createMessage" =>
        match sampling_h {
          Some(handler) =>
            match handler(params) {
              Ok(result) =>
                Json::object({
                  "jsonrpc": "2.0",
                  "id": id_json,
                  "result": serialize_create_message_result(result),
                }).stringify()
              Err(e) =>
                jsonrpc_error_str(id_json, e.to_error_code(), e.message())
            }
          None => jsonrpc_error_str(id_json, -32601, "sampling not supported")
        }
      "roots/list" =>
        match roots_h {
          Some(handler) =>
            match handler() {
              Ok(roots) =>
                Json::object({
                  "jsonrpc": "2.0",
                  "id": id_json,
                  "result": {
                    "roots": Json::array(
                      roots.map(fn(r) {
                        let root_map : Map[String, Json] = Default::default()
                        root_map.set("uri", Json::string(r.uri))
                        match r.name {
                          Some(n) => root_map.set("name", Json::string(n))
                          None => ()
                        }
                        Json::object(root_map)
                      }),
                    ),
                  },
                }).stringify()
              Err(e) =>
                jsonrpc_error_str(id_json, e.to_error_code(), e.message())
            }
          None => jsonrpc_error_str(id_json, -32601, "roots not supported")
        }
      "elicitation/create" =>
        match elicitation_h {
          Some(handler) =>
            match handler(params) {
              Ok(result) =>
                Json::object({
                  "jsonrpc": "2.0",
                  "id": id_json,
                  "result": {
                    "action": result.action,
                    "content": match result.content {
                      Some(c) => c
                      None => Json::null()
                    },
                  },
                }).stringify()
              Err(e) =>
                jsonrpc_error_str(id_json, e.to_error_code(), e.message())
            }
          None =>
            jsonrpc_error_str(id_json, -32601, "elicitation not supported")
        }
      _ =>
        jsonrpc_error_str(id_json, -32601, "Method not found: " + method_name)
    }
    transport.send(response) catch {
      _ => ()
    }
  })
}

/// === JSON parsing helpers ===

///|

///|
/// Extract a subscription id from notification `params._meta`. Accepts both
/// Number and String values and normalizes to a String so it matches the keys
/// used in `subscription_handlers`.
fn extract_subscription_id(params : Json?) -> String? {
  match params {
    Some(Object(obj)) =>
      match obj.get("_meta") {
        Some(Object(meta)) =>
          match meta.get("io.modelcontextprotocol/subscriptionId") {
            Some(Number(n, ..)) => Some(n.to_int().to_string())
            Some(String(s)) => Some(s)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_jsonrpc_response(
  response_str : String,
) -> Result[Json, @types.MCPError] {
  let json = @json.parse(response_str) catch {
    _ => return Err(@types.ParseError("Invalid JSON response"))
  }
  match json {
    Object(obj) => {
      match obj.get("error") {
        Some(Object(err_obj)) => {
          let message = match err_obj.get("message") {
            Some(String(m)) => m
            _ => "Unknown error"
          }
          return Err(@types.InternalError("Server error: " + message))
        }
        _ => ()
      }
      match obj.get("result") {
        Some(result_json) => Ok(result_json)
        None => Err(@types.InvalidRequest("Response missing 'result' field"))
      }
    }
    _ => Err(@types.ParseError("Response must be a JSON object"))
  }
}

///|
fn parse_tool_def(json : Json) -> @types.ToolDefinition? {
  match json {
    Object(obj) => {
      let name = match obj.get("name") {
        Some(String(n)) => n
        _ => return None
      }
      let description = match obj.get("description") {
        Some(String(d)) => d
        _ => ""
      }
      let input_schema = obj.get("inputSchema").unwrap_or(Json::null())
      Some({ name, description, input_schema, })
    }
    _ => None
  }
}

///|
/// Parse `server/discover` result capabilities into `ServerCapabilities`.
/// The 2026-07-28 spec advertises `tools`/`resources`/`prompts` each with an
/// optional `listChanged` flag. `subscribe` is a legacy field kept on the
/// struct for back-compat; discover no longer advertises it.
fn parse_discover_capabilities(result : Json) -> @types.ServerCapabilities {
  let tools = if result is Object(obj) {
    match obj.get("capabilities") {
      Some(Object(caps)) =>
        match caps.get("tools") {
          Some(Object(t)) =>
            Some(@types.ToolCapabilities::{
              list_changed: match
                t.get("listChanged").unwrap_or(Json::boolean(false)) {
                True => true
                False => false
                _ => false
              },
            })
          _ => None
        }
      _ => None
    }
  } else {
    None
  }
  let resources = if result is Object(obj) {
    match obj.get("capabilities") {
      Some(Object(caps)) =>
        match caps.get("resources") {
          Some(Object(r)) =>
            Some(@types.ResourceCapabilities::{
              subscribe: false,
              list_changed: match
                r.get("listChanged").unwrap_or(Json::boolean(false)) {
                True => true
                False => false
                _ => false
              },
            })
          _ => None
        }
      _ => None
    }
  } else {
    None
  }
  let prompts = if result is Object(obj) {
    match obj.get("capabilities") {
      Some(Object(caps)) =>
        match caps.get("prompts") {
          Some(Object(p)) =>
            Some(@types.PromptCapabilities::{
              list_changed: match
                p.get("listChanged").unwrap_or(Json::boolean(false)) {
                True => true
                False => false
                _ => false
              },
            })
          _ => None
        }
      _ => None
    }
  } else {
    None
  }
  let extensions = if result is Object(obj) {
    match obj.get("capabilities") {
      Some(Object(caps)) =>
        match caps.get("extensions") {
          Some(Object(ext)) => {
            let ext_map : Map[String, Json] = Default::default()
            ext.each(fn(k, v) { ext_map.set(k, v) })
            Some(ext_map)
          }
          _ => None
        }
      _ => None
    }
  } else {
    None
  }
  { tools, resources, prompts, extensions, }
}

///|
/// Extract `serverInfo` from a result's `_meta.io.modelcontextprotocol/serverInfo`.
/// Per the 2026-07-28 spec, server identity rides in `_meta`, not at the result
/// top level (unlike the legacy initialize response).
fn parse_server_info_from_result(result : Json) -> @types.ServerInfo? {
  if result is Object(obj) {
    match obj.get("_meta") {
      Some(Object(meta)) =>
        match meta.get("io.modelcontextprotocol/serverInfo") {
          Some(Object(info)) =>
            Some(@types.ServerInfo::{
              name: match info.get("name") {
                Some(String(s)) => s
                _ => ""
              },
              title: match info.get("title") {
                Some(String(t)) => Some(t)
                _ => None
              },
              version: match info.get("version") {
                Some(String(s)) => s
                _ => ""
              },
              description: match info.get("description") {
                Some(String(d)) => Some(d)
                _ => None
              },
            })
          _ => None
        }
      _ => None
    }
  } else {
    None
  }
}

///|
fn parse_tools_list(
  result_json : Json,
) -> Result[ListToolsResult, @types.MCPError] {
  match result_json {
    Object(obj) =>
      match obj.get("tools") {
        Some(Array(tools_json)) => {
          let next_cursor = match obj.get("nextCursor") {
            Some(String(c)) => Some(c)
            _ => None
          }
          Ok({ tools: tools_json.filter_map(parse_tool_def), next_cursor, })
        }
        _ => Err(@types.InvalidRequest("Missing 'tools' array in result"))
      }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_call_tool(
  result_json : Json,
) -> Result[CallToolResult, @types.MCPError] {
  match result_json {
    Object(obj) => {
      let content_items = match obj.get("content") {
        Some(Array(items)) => items.filter_map(parse_content_item)
        _ => []
      }
      let is_error = match obj.get("isError") {
        Some(True) => true
        _ => false
      }
      Ok({ content: content_items, is_error, })
    }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_content_item(json : Json) -> @types.ContentItem? {
  match json {
    Object(obj) => {
      let type_ = match obj.get("type") {
        Some(String(t)) => t
        _ => return None
      }
      match type_ {
        "text" =>
          match obj.get("text") {
            Some(String(t)) => Some(@types.ContentItem::Text(t))
            _ => None
          }
        "image" =>
          match obj.get("data") {
            Some(String(d)) => {
              let mime_type = match obj.get("mimeType") {
                Some(String(m)) => m
                _ => "image/png"
              }
              Some(@types.ContentItem::Image(d, mime_type~))
            }
            _ => None
          }
        "resource_link" =>
          match obj.get("uri") {
            Some(String(u)) => Some(@types.ContentItem::ResourceLink(u))
            _ => None
          }
        "resource" =>
          match obj.get("resource") {
            Some(Object(res_obj)) =>
              match res_obj.get("uri") {
                Some(String(u)) =>
                  match res_obj.get("text") {
                    Some(String(t)) => {
                      let mime_type = match res_obj.get("mimeType") {
                        Some(String(m)) => Some(m)
                        _ => None
                      }
                      Some(
                        @types.ContentItem::EmbeddedResource(
                          @types.EmbeddedResourceContent::Text(
                            t,
                            uri=u,
                            mime_type~,
                          ),
                        ),
                      )
                    }
                    _ => None
                  }
                _ => None
              }
            _ => None
          }
        _ => None
      }
    }
    _ => None
  }
}

///|
fn parse_resource_def(json : Json) -> @resource.ResourceDefinition? {
  match json {
    Object(obj) =>
      match obj.get("uri") {
        Some(String(u)) =>
          match obj.get("name") {
            Some(String(n)) => {
              let description = match obj.get("description") {
                Some(String(d)) => Some(d)
                _ => None
              }
              let mime_type = match obj.get("mimeType") {
                Some(String(m)) => Some(m)
                _ => None
              }
              Some({ uri: u, name: n, description, mime_type, })
            }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_list_resources(
  result_json : Json,
) -> Result[ListResourcesResult, @types.MCPError] {
  match result_json {
    Object(obj) =>
      match obj.get("resources") {
        Some(Array(resources_json)) => {
          let next_cursor = match obj.get("nextCursor") {
            Some(String(c)) => Some(c)
            _ => None
          }
          Ok({
            resources: resources_json.filter_map(parse_resource_def),
            next_cursor,
          })
        }
        _ => Err(@types.InvalidRequest("Missing 'resources' array in result"))
      }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_resource_content(json : Json) -> @resource.ResourceReadResult? {
  match json {
    Object(obj) =>
      match obj.get("uri") {
        Some(String(u)) => {
          let content = match obj.get("text") {
            Some(String(t)) => @resource.ResourceContent::Text(t)
            None =>
              match obj.get("blob") {
                Some(String(b)) => {
                  let mime_type = match obj.get("mimeType") {
                    Some(String(m)) => m
                    _ => "application/octet-stream"
                  }
                  @resource.ResourceContent::Blob(b, mime_type~)
                }
                _ => return None
              }
            _ => return None
          }
          Some({ uri: u, content, })
        }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_read_resource(
  result_json : Json,
) -> Result[ReadResourceResult, @types.MCPError] {
  match result_json {
    Object(obj) =>
      match obj.get("contents") {
        Some(Array(contents_json)) =>
          Ok({ contents: contents_json.filter_map(parse_resource_content), })
        _ => Err(@types.InvalidRequest("Missing 'contents' array in result"))
      }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_prompt_arg(json : Json) -> @types.PromptArgument? {
  match json {
    Object(obj) =>
      match obj.get("name") {
        Some(String(n)) => {
          let description = match obj.get("description") {
            Some(String(d)) => Some(d)
            _ => None
          }
          let required = match obj.get("required") {
            Some(True) => Some(true)
            Some(False) => Some(false)
            _ => None
          }
          Some({ name: n, description, required, })
        }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_prompt_def(json : Json) -> @prompt.PromptDefinition? {
  match json {
    Object(obj) =>
      match obj.get("name") {
        Some(String(n)) => {
          let description = match obj.get("description") {
            Some(String(d)) => Some(d)
            _ => None
          }
          let arguments = match obj.get("arguments") {
            Some(Array(args_json)) =>
              Some(args_json.filter_map(parse_prompt_arg))
            _ => None
          }
          Some({ name: n, description, arguments, })
        }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_list_prompts(
  result_json : Json,
) -> Result[ListPromptsResult, @types.MCPError] {
  match result_json {
    Object(obj) =>
      match obj.get("prompts") {
        Some(Array(prompts_json)) => {
          let next_cursor = match obj.get("nextCursor") {
            Some(String(c)) => Some(c)
            _ => None
          }
          Ok({
            prompts: prompts_json.filter_map(parse_prompt_def),
            next_cursor,
          })
        }
        _ => Err(@types.InvalidRequest("Missing 'prompts' array in result"))
      }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_prompt_message(json : Json) -> @types.PromptMessage? {
  match json {
    Object(obj) =>
      match obj.get("role") {
        Some(String(role)) =>
          match obj.get("content") {
            Some(content_json) =>
              match parse_content_item(content_json) {
                Some(item) => Some({ role, content: item, })
                None => None
              }
            None => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_get_prompt(
  result_json : Json,
) -> Result[@types.GetPromptResult, @types.MCPError] {
  match result_json {
    Object(obj) => {
      let description = match obj.get("description") {
        Some(String(d)) => Some(d)
        _ => None
      }
      match obj.get("messages") {
        Some(Array(msgs_json)) =>
          Ok({
            description,
            messages: msgs_json.filter_map(parse_prompt_message),
          })
        _ => Err(@types.InvalidRequest("Missing 'messages' array in result"))
      }
    }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_resource_template(json : Json) -> ResourceTemplate? {
  match json {
    Object(obj) =>
      match obj.get("uriTemplate") {
        Some(String(u)) =>
          match obj.get("name") {
            Some(String(n)) => {
              let description = match obj.get("description") {
                Some(String(d)) => Some(d)
                _ => None
              }
              let mime_type = match obj.get("mimeType") {
                Some(String(m)) => Some(m)
                _ => None
              }
              Some({ uri_template: u, name: n, description, mime_type, })
            }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_list_resource_templates(
  result_json : Json,
) -> Result[ListResourceTemplatesResult, @types.MCPError] {
  match result_json {
    Object(obj) =>
      match obj.get("resourceTemplates") {
        Some(Array(templates_json)) => {
          let next_cursor = match obj.get("nextCursor") {
            Some(String(c)) => Some(c)
            _ => None
          }
          Ok({
            resource_templates: templates_json.filter_map(
              parse_resource_template,
            ),
            next_cursor,
          })
        }
        _ =>
          Err(
            @types.InvalidRequest("Missing 'resourceTemplates' array in result"),
          )
      }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
/// Parse a `completion/complete` result. The 2026-07-28 schema nests the
/// payload under `result.completion` (`CompleteResult`), so the fields are
/// read from that object; a missing or non-object `completion` is an
/// InvalidParams error.
fn parse_completion_result(
  result_json : Json,
) -> Result[CompletionResult, @types.MCPError] {
  match result_json {
    Object(obj) =>
      match obj.get("completion") {
        Some(Object(completion)) =>
          match completion.get("values") {
            Some(Array(values_json)) => {
              let values = values_json.filter_map(fn(v) {
                match v {
                  String(s) => Some(s)
                  _ => None
                }
              })
              let total = match completion.get("total") {
                Some(Number(n, ..)) => Some(n.to_int())
                _ => None
              }
              let has_more = match completion.get("hasMore") {
                Some(True) => Some(true)
                Some(False) => Some(false)
                _ => None
              }
              Ok({ values, total, has_more, })
            }
            _ =>
              Err(@types.InvalidParams("Missing 'values' array in completion"))
          }
        _ => Err(@types.InvalidParams("Missing 'completion' object in result"))
      }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn request_id_to_json(id : @types.RequestId) -> Json {
  match id {
    Int(n) => Json::number(n.to_double())
    Str(s) => Json::string(s)
  }
}

///|
fn jsonrpc_error_str(id_json : Json, code : Int, message : String) -> String {
  Json::object({
    "jsonrpc": "2.0",
    "id": id_json,
    "error": { "code": code, "message": message },
  }).stringify()
}

///|
fn serialize_create_message_result(result : @types.CreateMessageResult) -> Json {
  let obj_map : Map[String, Json] = Default::default()
  obj_map.set("role", Json::string(result.role))
  obj_map.set("model", Json::string(result.model))
  obj_map.set("content", serialize_content_item(result.content))
  match result.stop_reason {
    Some(r) => obj_map.set("stopReason", Json::string(r))
    None => ()
  }
  Json::object(obj_map)
}

///|
fn serialize_content_item(item : @types.ContentItem) -> Json {
  match item {
    Text(t) => Json::object({ "type": "text", "text": t })
    Image(data, mime_type~) =>
      Json::object({ "type": "image", "data": data, "mimeType": mime_type })
    ResourceLink(uri) => Json::object({ "type": "resource_link", "uri": uri })
    EmbeddedResource(content) =>
      match content {
        Text(t, uri~, mime_type~) => {
          let res_map : Map[String, Json] = Default::default()
          res_map.set("uri", Json::string(uri))
          res_map.set("text", Json::string(t))
          match mime_type {
            Some(m) => res_map.set("mimeType", Json::string(m))
            None => ()
          }
          Json::object({ "type": "resource", "resource": Json::object(res_map) })
        }
        Blob(b, uri~, mime_type~) =>
          Json::object({
            "type": "resource",
            "resource": { "uri": uri, "blob": b, "mimeType": mime_type },
          })
      }
  }
}
