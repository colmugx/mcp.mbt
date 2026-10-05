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
  request_cancellations : Map[Int, (String?) -> Unit]
  receive_mutex : @async.Mutex
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
    request_cancellations: {},
    receive_mutex: @async.Mutex::Mutex(),
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
  @types.ClientCapabilities::new()
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
  let id = extract_request_id(request)
  let explicitly_cancelled = Ref(false)
  let cancellation_reason : Ref[String?] = Ref(None)
  @async.with_task_group(group => {
    let owned_task : Ref[@async.Task[Result[String, @types.MCPError]]?] = Ref(
      None,
    )
    self.request_cancellations.set(id, fn(reason) {
      cancellation_reason.val = reason
      explicitly_cancelled.val = true
      match owned_task.val {
        Some(task) => task.cancel()
        None => ()
      }
    })
    defer self.request_cancellations.remove(id)
    let task = group.spawn(
      () => self.send_request_inner(request, cancellation_reason),
      allow_failure=true,
    )
    owned_task.val = Some(task)
    if explicitly_cancelled.val {
      task.cancel()
    }
    task.wait() catch {
      error =>
        if explicitly_cancelled.val && @async.is_cancellation_error(error) {
          Err(@types.Cancelled("Request cancelled by client"))
        } else {
          raise error
        }
    }
  })
}

///|
async fn MCPClient::send_request_inner(
  self : MCPClient,
  request : String,
  cancellation_reason : Ref[String?],
) -> Result[String, @types.MCPError] {
  let id = extract_request_id(request)
  let queue : @aqueue.Queue[String] = @aqueue.Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  self.response_map[id] = queue
  defer self.response_map.remove(id)
  @async.with_task_group(group => {
    if !self.event_loop_started {
      group.spawn_bg(() => self.pump_direct_responses(group), no_wait=true)
    }
    self.transport.send(request) catch {
      error => {
        if @async.is_being_cancelled() {
          self.notify_cancelled_best_effort(
            @types.RequestId::Int(id),
            reason?=cancellation_reason.val,
          )
          raise error
        }
        return Err(@types.InternalError("Send failed: " + error.to_string()))
      }
    }
    let response = queue.get() catch {
      error => {
        if @async.is_being_cancelled() {
          self.notify_cancelled_best_effort(
            @types.RequestId::Int(id),
            reason?=cancellation_reason.val,
          )
          raise error
        }
        return Err(
          @types.InternalError("Response stream closed: " + error.to_string()),
        )
      }
    }
    self.maybe_store_server_info(response)
    Ok(response)
  })
}

///|
/// Best-effort `notifications/cancelled` when task cancellation aborts an
/// in-flight request: `send_request` calls this right before re-raising the
/// cancellation. Mirrors `cancel_request` transport gating (stdio client
/// transports only; HTTP cancels by closing the SSE stream). The write is
/// shielded with `protect_from_cancel` so the level-triggered cancellation
/// cannot kill it mid-write. A one-second timeout bounds backpressure or lock
/// waits; failures are swallowed because the caller is already unwinding.
async fn MCPClient::notify_cancelled_best_effort(
  self : MCPClient,
  request_id : @types.RequestId,
  reason? : String,
) -> Unit {
  match self.transport {
    @transport.AnyTransport::StdioClient(_) => {
      let notif = @types.cancelled_notification(
        request_id,
        reason=reason.unwrap_or("client aborted"),
      )
      let t = self.transport
      @async.protect_from_cancel(() => {
        ignore(@async.with_timeout_opt(1000, () => t.send_notification(notif))) catch {
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
  let json = @validation.parse_json(response_str) catch { _ => return }
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
          Ok(Some(input_req)) => {
            if rounds == max_rounds {
              return Err(@types.InternalError("MRTR exceeded max rounds"))
            }
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
  let json = @validation.parse_json(response) catch { _ => return Ok(None) }
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
  if !result.contains("inputRequests") && !result.contains("requestState") {
    return Err(
      @types.InvalidParams(
        "input_required must contain inputRequests or requestState",
      ),
    )
  }
  let reqs : Map[String, (String, Json)] = Map([])
  match result.get("inputRequests") {
    None => ()
    Some(Object(map)) =>
      for key, value in map {
        guard value is Object(entry) else {
          return Err(
            @types.InvalidParams("Input request '\{key}' must be an object"),
          )
        }
        let method_name = match entry.get("method") {
          Some(String(method_name)) => method_name
          _ =>
            return Err(
              @types.InvalidParams(
                "Input request '\{key}' requires a string method",
              ),
            )
        }
        let params = match entry.get("params") {
          Some(Object(fields)) => Json::object(fields)
          None if method_name == "roots/list" => Json::object({})
          _ =>
            return Err(
              @types.InvalidParams(
                "Input request '\{key}' requires object params",
              ),
            )
        }
        reqs.set(key, (method_name, params))
      }
    Some(_) =>
      return Err(@types.InvalidParams("inputRequests must be an object"))
  }
  let request_state = match result.get("requestState") {
    None => None
    Some(String(state)) => Some(state)
    Some(_) => return Err(@types.InvalidParams("requestState must be a string"))
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
          Some(handler) => {
            let request = @types.ElicitationRequest::from_json(params) catch {
              e => {
                error = Some(e)
                return
              }
            }
            if request is @types.ElicitationRequest::Url(_, ..) &&
              !(self.capabilities.elicitation is Some(cap) && cap.url is Some(_)) {
              error = Some(
                @types.MissingRequiredClientCapability(
                  "URL elicitation was not advertised",
                  required=@types.ClientCapabilities::new(
                    elicitation=@types.ElicitationCapabilities::new(url={}),
                  ),
                ),
              )
              return
            }
            if request is @types.ElicitationRequest::Form(_, ..) &&
              !(self.capabilities.elicitation is Some(cap) &&
              (cap.form is Some(_) || cap.url is None)) {
              error = Some(
                @types.MissingRequiredClientCapability(
                  "Form elicitation was not advertised",
                  required=@types.ClientCapabilities::new(
                    elicitation=@types.ElicitationCapabilities::new(form={}),
                  ),
                ),
              )
              return
            }
            let response = invoke_elicitation(handler, params) catch {
              e => {
                error = Some(e)
                return
              }
            }
            responses.set(key, response)
          }
          None =>
            error = Some(
              @types.MissingRequiredClientCapability(
                "no elicitation handler registered",
                required=@types.ClientCapabilities::new(
                  elicitation=@types.ElicitationCapabilities::new(form={}),
                ),
              ),
            )
        }
      "sampling/createMessage" =>
        match self.sampling_handler {
          Some(handler) => {
            let request = @types.CreateMessageRequest::from_json(params) catch {
              e => {
                error = Some(e)
                return
              }
            }
            let needs_tools = request.tools is Some(_) ||
              request.tool_choice is Some(_)
            if !(self.capabilities.sampling is Some(cap) &&
              (!needs_tools || cap.tools is Some(_))) {
              error = Some(
                @types.MissingRequiredClientCapability(
                  "Sampling capability was not advertised",
                  required=@types.ClientCapabilities::new(
                    sampling=if needs_tools {
                      @types.SamplingCapabilities::new(tools=Map([]))
                    } else {
                      @types.SamplingCapabilities::new()
                    },
                  ),
                ),
              )
              return
            }
            match handler(params) {
              Ok(r) => {
                let response = sampling_result_to_json(r)
                ignore(@types.CreateMessageResult::from_json(response)) catch {
                  e => {
                    error = Some(e)
                    return
                  }
                }
                responses.set(key, response)
              }
              Err(e) => error = Some(e)
            }
          }
          None =>
            error = Some(
              @types.MissingRequiredClientCapability(
                "no sampling handler registered",
                required=@types.ClientCapabilities::new(
                  sampling=@types.SamplingCapabilities::new(),
                ),
              ),
            )
        }
      "roots/list" =>
        match self.roots_handler {
          Some(handler) => {
            if self.capabilities.roots is None {
              error = Some(
                @types.MissingRequiredClientCapability(
                  "Roots capability was not advertised",
                  required=@types.ClientCapabilities::new(
                    roots=@types.RootCapabilities::new(),
                  ),
                ),
              )
              return
            }
            @validation.check_roots_request(params) catch {
              e => {
                error = Some(e)
                return
              }
            }
            match handler() {
              Ok(roots) => {
                let response = roots_to_json(roots)
                @validation.check_roots_response(response) catch {
                  e => {
                    error = Some(e)
                    return
                  }
                }
                responses.set(key, response)
              }
              Err(e) => error = Some(e)
            }
          }
          None =>
            error = Some(
              @types.MissingRequiredClientCapability(
                "no roots handler registered",
                required=@types.ClientCapabilities::new(
                  roots=@types.RootCapabilities::new(),
                ),
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
  let orig = @validation.parse_json(original) catch { _ => return original }
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
fn sampling_result_to_json(r : @types.CreateMessageResult) -> Json {
  r.to_json()
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
/// Cancel a locally owned request and release its caller. Stdio also sends
/// `notifications/cancelled` with the original id type; HTTP cancels by closing
/// the owned response stream, never by sending a cancellation POST. An unknown
/// HTTP id cannot identify a stream to close.
pub async fn MCPClient::cancel_request(
  self : MCPClient,
  request_id : @types.RequestId,
  reason? : String,
) -> Result[Unit, @types.MCPError] {
  if self.backend is Legacy(_) {
    return Err(
      @types.MethodNotFound(
        "request cancellation is not supported by the legacy fallback client",
      ),
    )
  }
  if request_id is @types.RequestId::Int(id) {
    match self.request_cancellations.get(id) {
      Some(cancel) => {
        cancel(reason)
        return Ok(())
      }
      None => ()
    }
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
          "No active HTTP request with this id; cancellation requires a request owned by this client",
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
              let caps = parse_discover_capabilities(result_json) catch {
                error => return Err(error)
              }
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
              let caps = parse_discover_capabilities(result_json) catch {
                error => return Err(error)
              }
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
                    metadata: list_result.metadata,
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
  progress_token? : @types.ProgressToken,
) -> Result[CallToolResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_tools_call_request(
    id,
    name,
    self.request_meta(),
    arguments~,
    progress_token?,
  ) catch {
    error => return Err(error)
  }
  // Legacy backends: plain send/receive, no MRTR (a 2026-07-28 mechanism).
  if self.backend is Legacy(legacy) {
    return legacy_send_and_parse(
      legacy,
      apply_legacy_meta_to_request(request, build_legacy_meta(progress_token?)),
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
  ) catch {
    error => return Err(error)
  }
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
  context_arguments? : Map[String, String],
) -> Result[CompletionResult, @types.MCPError] {
  let reference = match ref_type {
    "ref/prompt" => @types.CompletionReference::prompt(ref_name)
    "ref/resource" => @types.CompletionReference::resource(ref_name)
    _ => return Err(@types.InvalidParams("Unknown completion reference type"))
  }
  self.complete_reference(
    reference,
    argument_name~,
    argument_value~,
    context_arguments?,
  )
}

///|
pub async fn MCPClient::complete_reference(
  self : MCPClient,
  reference : @types.CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
) -> Result[CompletionResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_completion_reference_request(
    id,
    self.request_meta(),
    reference,
    argument_name~,
    argument_value~,
    context_arguments?,
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
  self.cancel_owned_requests("client closed")
  match self.backend {
    Legacy(legacy) => legacy.close()
    Modern => self.transport.close()
  }
}

///|
fn MCPClient::cancel_owned_requests(self : MCPClient, reason : String) -> Unit {
  let cancellations = self.request_cancellations.values().collect()
  for cancel in cancellations {
    cancel(Some(reason))
  }
}

/// === Bidirectional event loop ===

///|
pub fn MCPClient::on_sampling(
  self : MCPClient,
  handler : (Json) -> Result[@types.CreateMessageResult, @types.MCPError],
  capabilities? : @types.SamplingCapabilities,
) -> MCPClient {
  {
    ..self,
    sampling_handler: Some(handler),
    capabilities: {
      ..self.capabilities,
      sampling: Some(
        capabilities.unwrap_or(
          self.capabilities.sampling.unwrap_or(
            @types.SamplingCapabilities::new(),
          ),
        ),
      ),
    },
  }
}

///|
pub fn MCPClient::on_roots(
  self : MCPClient,
  handler : () -> Result[Array[@types.Root], @types.MCPError],
) -> MCPClient {
  {
    ..self,
    roots_handler: Some(handler),
    capabilities: {
      ..self.capabilities,
      roots: Some(
        self.capabilities.roots.unwrap_or(@types.RootCapabilities::new()),
      ),
    },
  }
}

///|
pub fn MCPClient::on_elicitation(
  self : MCPClient,
  handler : (Json) -> Result[@types.ElicitationResult, @types.MCPError],
  capabilities? : @types.ElicitationCapabilities,
) -> MCPClient {
  {
    ..self,
    elicitation_handler: Some(handler),
    capabilities: {
      ..self.capabilities,
      elicitation: Some(
        capabilities.unwrap_or(
          self.capabilities.elicitation.unwrap_or(
            @types.ElicitationCapabilities::new(form={}),
          ),
        ),
      ),
    },
  }
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
/// Cancel a locally owned `subscriptions/listen` request. Stdio sends the
/// cancellation notification; HTTP closes the owned subscription stream.
pub async fn MCPClient::cancel_listen(
  self : MCPClient,
  subscription_id : String,
) -> Result[Unit, @types.MCPError] {
  let parsed = @json.parse(subscription_id) catch {
    _ => return Err(@types.InvalidParams("Invalid subscription id"))
  }
  let id = match parsed {
    Number(value, ..) => @types.RequestId::Int(value.to_int())
    _ => return Err(@types.InvalidParams("Invalid subscription id"))
  }
  self.cancel_request(id, reason="client cancelled listen subscription")
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
  // Share read ownership with temporary pumps used by calls made before run().
  self.receive_mutex.acquire()
  defer self.receive_mutex.release()
  // Stateless 2026-07-28: no initialize handshake before the event loop.
  self.event_loop_started = true
  defer {
    self.event_loop_started = false
    self.cancel_owned_requests("client event loop stopped")
    self.close_pending_response_queues()
    self.subscription_handlers.clear()
  }
  while true {
    let msg_opt = self.transport.receive()
    match msg_opt {
      None => {
        self.transport.close()
        break
      }
      Some(message) => self.route_received_message(message, group)
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
fn[T] MCPClient::handle_server_request(
  self : MCPClient,
  obj : Map[String, Json],
  group : @async.TaskGroup[T],
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
            try invoke_elicitation(handler, params) catch {
              e => jsonrpc_error_str(id_json, e.to_error_code(), e.message())
            } noraise {
              result =>
                Json::object({
                  "jsonrpc": "2.0",
                  "id": id_json,
                  "result": result,
                }).stringify()
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
  let json = @validation.parse_json(response_str) catch {
    _ => return Err(@types.ParseError("Invalid JSON response"))
  }
  match json {
    Object(obj) => {
      match obj.get("error") {
        Some(value) => {
          if obj.contains("result") {
            return Err(
              @types.InvalidRequest(
                "Response must not contain both result and error",
              ),
            )
          }
          let error = @types.MCPError::from_jsonrpc_error(value) catch {
            error => return Err(error)
          }
          return Err(error)
        }
        None => ()
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
/// Parse all discovery capabilities without defaulting away absent fields.
fn parse_discover_capabilities(
  result : Json,
) -> @types.ServerCapabilities raise @types.MCPError {
  guard result is Object(fields) else {
    raise @types.InvalidParams("Discovery result must be an object")
  }
  match fields.get("capabilities") {
    Some(value) => @types.ServerCapabilities::from_json(value)
    None =>
      raise @types.InvalidParams("Discovery result is missing capabilities")
  }
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
            None => None
            _ => return Err(@types.InvalidParams("Invalid nextCursor string"))
          }
          let tools = tools_json.map(@types.ToolDefinition::from_json) catch {
            error => return Err(error)
          }
          let metadata = @types.ResultMetadata::from_json(result_json, body_fields=[
            "tools", "nextCursor",
          ]) catch {
            error => return Err(error)
          }
          Ok({ tools, next_cursor, metadata, })
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
  let result = @types.ToolResult::from_json(result_json) catch {
    error => return Err(error)
  }
  Ok(result)
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
            None => None
            _ => return Err(@types.InvalidParams("Invalid nextCursor string"))
          }
          let resources = resources_json.map(
            @types.ResourceDefinition::from_json,
          ) catch {
            error => return Err(error)
          }
          let metadata = @types.ResultMetadata::from_json(result_json, body_fields=[
            "resources", "nextCursor",
          ]) catch {
            error => return Err(error)
          }
          Ok({ resources, next_cursor, metadata, })
        }
        _ => Err(@types.InvalidRequest("Missing 'resources' array in result"))
      }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_read_resource(
  result_json : Json,
) -> Result[ReadResourceResult, @types.MCPError] {
  let result = @types.ResourceReadResult::from_json(result_json) catch {
    error => return Err(error)
  }
  Ok({ contents: result.contents, metadata: result.metadata, })
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
            None => None
            _ => return Err(@types.InvalidParams("Invalid nextCursor string"))
          }
          let prompts = prompts_json.map(@types.PromptDefinition::from_json) catch {
            error => return Err(error)
          }
          let metadata = @types.ResultMetadata::from_json(result_json, body_fields=[
            "prompts", "nextCursor",
          ]) catch {
            error => return Err(error)
          }
          Ok({ prompts, next_cursor, metadata, })
        }
        _ => Err(@types.InvalidRequest("Missing 'prompts' array in result"))
      }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_get_prompt(
  result_json : Json,
) -> Result[@types.GetPromptResult, @types.MCPError] {
  let result = @types.GetPromptResult::from_json(result_json) catch {
    error => return Err(error)
  }
  Ok(result)
}

///|
fn parse_resource_template(
  json : Json,
) -> ResourceTemplate raise @types.MCPError {
  let template = @types.ResourceTemplateDefinition::from_json(json)
  {
    uri_template: template.uri_template,
    name: template.name,
    title: template.title,
    description: template.description,
    mime_type: template.mime_type,
    icons: template.icons,
    metadata: template.metadata,
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
            None => None
            _ => return Err(@types.InvalidParams("Invalid nextCursor string"))
          }
          let resource_templates = templates_json.map(parse_resource_template) catch {
            error => return Err(error)
          }
          let metadata = @types.ResultMetadata::from_json(result_json, body_fields=[
            "resourceTemplates", "nextCursor",
          ]) catch {
            error => return Err(error)
          }
          Ok({ resource_templates, next_cursor, metadata, })
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
  try @types.CompletionResult::from_json(result_json) catch {
    error => Err(error)
  } noraise {
    result => Ok(result)
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
  result.to_json()
}

///|
pub extend ProtocolEra with Eq::{not_equal, equal}
