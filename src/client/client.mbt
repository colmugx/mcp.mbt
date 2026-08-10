///|
struct RequestIdCounter {
  mut next_id : Int
}

///|
fn RequestIdCounter::RequestIdCounter() -> RequestIdCounter {
  { next_id: 0 }
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
    sampling_handler: None,
    roots_handler: None,
    elicitation_handler: None,
    response_map: {},
    event_loop_started: false,
  }
}

///|
pub fn MCPClient::connect_http(
  url~ : String,
  name~ : String,
  version~ : String,
  auth_token? : String = "",
) -> Result[MCPClient, @types.MCPError] {
  // 2026-07-28 is stateless: no initialize handshake. The client is ready to
  // send per-request _meta immediately. (Era probing for legacy 2025-11-25
  // servers lives in the legacy package; modern-only deployments use this.)
  let transport = @transport.AnyTransport::HttpClient(
    @transport.HttpClientTransport::HttpClientTransport(url, auth_token~),
  )
  Ok(MCPClient::MCPClient(name~, version~, transport~))
}

///|
pub async fn MCPClient::connect_stdio(
  cmd~ : String,
  args? : Array[String] = [],
  name~ : String,
  version~ : String,
  extra_env? : Map[String, String] = {},
  group~ : @async.TaskGroup[Unit],
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
  Ok(MCPClient::MCPClient(name~, version~, transport~))
}

///|
fn default_capabilities() -> @types.ClientCapabilities {
  {
    roots: Some({ list_changed: true }),
    sampling: Some(@types.SamplingCapabilities::{  }),
    elicitation: Some({ form: true }),
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
      _ => {
        self.response_map.remove(id)
        return Err(@types.InternalError("Response timeout"))
      }
    }
    Ok(response)
  } else {
    // Legacy mode: direct send/receive
    let t = self.transport
    t.send(request) catch {
      e => return Err(@types.InternalError("Send failed: " + e.to_string()))
    }
    let response = t.receive() catch {
      e => return Err(@types.InternalError("Receive failed: " + e.to_string()))
    }
    match response {
      Some(msg) => Ok(msg)
      None => Err(@types.InternalError("Connection closed"))
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
/// per spec (back-compat with older servers).
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
          None => return Ok(response)
          Some(input_req) =>
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
/// If `response` is an `input_required` result, extract the `inputRequests`
/// map and `requestState`; otherwise return None (complete or error).
priv struct InputRequiredInfo {
  input_requests : Map[String, (String, Json)] // key -> (method, params)
  request_state : String?
} derive(Debug)

///|
fn MCPClient::check_input_required(
  self : MCPClient,
  response : String,
) -> InputRequiredInfo? {
  ignore(self)
  let json = @json.parse(response) catch { _ => return None }
  if !(json is Object(_)) {
    return None
  }
  let result = if json is Object(obj) {
    match obj.get("result") {
      Some(Object(r)) => r
      _ => return None
    }
  } else {
    return None
  }
  let result_type = match result.get("resultType") {
    Some(String(s)) => s
    _ => return None // absent => "complete"
  }
  if result_type != "input_required" {
    return None
  }
  let reqs : Map[String, (String, Json)] = Default::default()
  match result.get("inputRequests") {
    Some(Object(map)) =>
      map.each(fn(key, val) {
        if val is Object(entry) {
          let method = match entry.get("method") {
            Some(String(m)) => m
            _ => ""
          }
          let params = entry.get("params").unwrap_or(Json::null())
          reqs.set(key, (method, params))
        }
      })
    _ => ()
  }
  let request_state = match result.get("requestState") {
    Some(String(s)) => Some(s)
    _ => None
  }
  Some({ input_requests: reqs, request_state })
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
    let (method, params) = entry
    match method {
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
          @types.MethodNotFound("Unknown input request method: " + method),
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
async fn MCPClient::send_notification(
  self : MCPClient,
  notification : String,
) -> Result[Unit, @types.MCPError] {
  let t = self.transport
  let notif = @json.parse(notification) catch {
    _ => return Err(@types.ParseError("Invalid notification JSON"))
  }
  match notif {
    Object(obj) => {
      let method_name = match obj.get("method") {
        Some(String(m)) => m
        _ => return Err(@types.InvalidRequest("Missing method field"))
      }
      let params = obj.get("params")
      let notification_obj : @types.Notification = { method_name, params }
      t.send_notification(notification_obj) catch {
        e =>
          return Err(
            @types.InternalError("Notification failed: " + e.to_string()),
          )
      }
      Ok(())
    }
    _ => Err(@types.InvalidRequest("Notification must be a JSON object"))
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

///|
pub async fn MCPClient::list_tools(
  self : MCPClient,
  cursor? : String = "",
) -> Result[ListToolsResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_tools_list_request(id, self.request_meta(), cursor~)
  match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_tools_list(result_json)
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
pub fn MCPClient::close(self : MCPClient) -> Unit {
  self.transport.close()
}

/// === Bidirectional event loop ===

///|
pub fn MCPClient::on_sampling(
  self : MCPClient,
  handler : (Json) -> Result[@types.CreateMessageResult, @types.MCPError],
) -> MCPClient {
  { ..self, sampling_handler: Some(handler) }
}

///|
pub fn MCPClient::on_roots(
  self : MCPClient,
  handler : () -> Result[Array[@types.Root], @types.MCPError],
) -> MCPClient {
  { ..self, roots_handler: Some(handler) }
}

///|
pub fn MCPClient::on_elicitation(
  self : MCPClient,
  handler : (Json) -> Result[@types.ElicitationResult, @types.MCPError],
) -> MCPClient {
  { ..self, elicitation_handler: Some(handler) }
}

///|
pub fn MCPClient::on_notification(
  self : MCPClient,
  handlers : NotificationHandlers,
) -> MCPClient {
  { ..self, notification_handlers: handlers }
}

///|
pub async fn MCPClient::run(
  self : MCPClient,
  group : @async.TaskGroup[Unit],
) -> Unit {
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
              self.handle_server_request(obj, group)
            } else if obj.get("method") is Some(_) {
              let notif : @types.Notification = {
                method_name: match obj.get("method") {
                  Some(String(m)) => m
                  _ => continue
                },
                params: obj.get("params"),
              }
              handle_server_notification(self.notification_handlers, notif)
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
      Some({
        name,
        description,
        input_schema,
        cached_schema_json: "",
        icon: None,
      })
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
  { tools, resources, prompts }
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
          Ok({ tools: tools_json.filter_map(parse_tool_def), next_cursor })
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
      Ok({ content: content_items, is_error })
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
              Some({ uri: u, name: n, description, mime_type })
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
          Some({ uri: u, content })
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
          Ok({ contents: contents_json.filter_map(parse_resource_content) })
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
          Some({ name: n, description, required })
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
          Some({ name: n, description, arguments })
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
          Ok({ prompts: prompts_json.filter_map(parse_prompt_def), next_cursor })
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
                Some(item) => Some({ role, content: item })
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
              Some({ uri_template: u, name: n, description, mime_type })
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
fn parse_completion_result(
  result_json : Json,
) -> Result[CompletionResult, @types.MCPError] {
  match result_json {
    Object(obj) =>
      match obj.get("values") {
        Some(Array(values_json)) => {
          let values = values_json.filter_map(fn(v) {
            match v {
              String(s) => Some(s)
              _ => None
            }
          })
          let total = match obj.get("total") {
            Some(Number(n, ..)) => Some(n.to_int())
            _ => None
          }
          let has_more = match obj.get("hasMore") {
            Some(True) => Some(true)
            Some(False) => Some(false)
            _ => None
          }
          Ok({ values, total, has_more })
        }
        _ => Err(@types.InvalidRequest("Missing 'values' array in result"))
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
