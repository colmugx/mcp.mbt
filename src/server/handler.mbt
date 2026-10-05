///| MCP Server Request Handlers

///|
fn request_id_to_json(id : @types.RequestId) -> Json {
  match id {
    Int(n) => Json::number(n.to_double())
    Str(s) => Json::string(s)
  }
}

///|
/// Build the `_meta.io.modelcontextprotocol/serverInfo` value for a response.
/// `description` is optional on the spec's `Implementation` schema and is
/// emitted only when set (B10).
fn server_info_meta(server : MCPServer) -> Json {
  let info : Map[String, Json] = Map([])
  info.set("name", Json::string(server.name))
  info.set("version", Json::string(server.version))
  match server.title {
    Some(t) => info.set("title", Json::string(t))
    None => ()
  }
  match server.description {
    Some(d) => info.set("description", Json::string(d))
    None => ()
  }
  Json::object(info)
}

///|
/// Attach `_meta` (carrying `serverInfo`) and `resultType: "complete"` to a
/// result object. Per the 2026-07-28 spec every result carries a `resultType`;
/// `input_required` results are built separately by `input_required_result`.
/// If `result` is not a JSON object, it is returned unchanged.
fn with_server_meta(server : MCPServer, result : Json) -> Json {
  match result {
    Object(obj) => {
      let fields = obj.copy()
      let meta = match obj.get("_meta") {
        Some(Object(meta)) => meta.copy()
        _ => Map([])
      }
      meta.set("io.modelcontextprotocol/serverInfo", server_info_meta(server))
      fields.set("resultType", Json::string("complete"))
      fields.set("_meta", Json::object(meta))
      Json::object(fields)
    }
    _ => result
  }
}

///|
/// Build an `InputRequiredResult` object: `resultType: "input_required"` with
/// `inputRequests` (server→client requests the client must fulfill) and an
/// optional `requestState` blob (opaque to the client, verified on retry).
/// `_meta` carries `serverInfo` as usual.
fn input_required_result(
  server : MCPServer,
  input_requests : Map[String, @types.InputRequestEntry],
  request_state? : String? = None,
) -> Json {
  let reqs_map : Map[String, Json] = Default::default()
  input_requests.each(fn(key, entry) {
    reqs_map.set(
      key,
      Json::object({
        "method": Json::string(entry.method_name.to_method()),
        "params": entry.params,
      }),
    )
  })
  let result : Map[String, Json] = Default::default()
  result.set("resultType", Json::string("input_required"))
  result.set("inputRequests", Json::object(reqs_map))
  match request_state {
    Some(rs) => result.set("requestState", Json::string(rs))
    None => ()
  }
  result.set(
    "_meta",
    Json::object({
      "io.modelcontextprotocol/serverInfo": server_info_meta(server),
    }),
  )
  Json::object(result)
}

///|
/// Serialize an `InputRequiredResult` Json into a full JSON-RPC success response.
fn jsonrpc_input_required_str(
  server : MCPServer,
  id : @types.RequestId,
  input_requests : Map[String, @types.InputRequestEntry],
  request_state? : String? = None,
) -> String {
  let result = input_required_result(server, input_requests, request_state~)
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": request_id_to_json(id),
    "result": result,
  }).stringify()
}

///|
fn jsonrpc_success_str(
  server : MCPServer,
  id : @types.RequestId,
  result : Json,
) -> String {
  ignore(@types.ResultMetadata::from_json(result, body_fields=[])) catch {
    _ =>
      return jsonrpc_error_str(
        id, -32603, "Handler returned invalid result metadata",
      )
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": request_id_to_json(id),
    "result": with_server_meta(server, result),
  }).stringify()
}

///|
/// Like `jsonrpc_success_str`, but also injects `ttlMs` + `cacheScope` into
/// the result for cacheable endpoints (tools/list, prompts/list,
/// resources/list, resources/read, server/discover) per spec
/// server/utilities/caching#cacheable-results (SEP-2549).
/// `ttl_ms` is a freshness hint in milliseconds (clients may cache the
/// response up to that long); `cache_scope` is "public" or "private".
fn jsonrpc_cacheable_success_str(
  server : MCPServer,
  id : @types.RequestId,
  result : Json,
  ttl_ms : Int,
  cache_scope : String,
) -> String {
  ignore(@types.ResultMetadata::from_json(result, body_fields=[])) catch {
    _ =>
      return jsonrpc_error_str(
        id, -32603, "Handler returned invalid result metadata",
      )
  }
  let result = with_server_meta(server, result)
  match result {
    Object(obj) => {
      if !obj.contains("ttlMs") {
        obj.set("ttlMs", Json::number(ttl_ms.to_double()))
      }
      if !obj.contains("cacheScope") {
        obj.set("cacheScope", Json::string(cache_scope))
      }
    }
    _ => ()
  }
  jsonrpc_success_str(server, id, result)
}

///|
fn jsonrpc_error_str(
  id : @types.RequestId,
  code : Int,
  message : String,
  data? : Json? = None,
) -> String {
  let error_map : Map[String, Json] = Default::default()
  error_map.set("code", Json::number(code.to_double()))
  error_map.set("message", Json::string(message))
  match data {
    Some(d) => error_map.set("data", d)
    None => ()
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": request_id_to_json(id),
    "error": Json::object(error_map),
  }).stringify()
}

///|
/// JSON-RPC error response with the `id` member omitted. Used when the
/// request could not be parsed, so no trustworthy id exists: JSON-RPC 2.0
/// says the id is null/absent there, while MCP forbids null ids — omitting
/// the field satisfies both. A fixed placeholder id (e.g. 0) would misroute
/// the error onto a live request that genuinely used that id.
fn jsonrpc_error_str_no_id(code : Int, message : String) -> String {
  let error_map : Map[String, Json] = Default::default()
  error_map.set("code", Json::number(code.to_double()))
  error_map.set("message", Json::string(message))
  Json::object({ "jsonrpc": "2.0", "error": Json::object(error_map) }).stringify()
}

///|
/// Build a JSON-RPC error response from an `MCPError`, automatically
/// populating the `data` member for spec-defined errors
/// (`UnsupportedProtocolVersion`, `MissingRequiredClientCapability`).
fn jsonrpc_error_from(id : @types.RequestId, err : @types.MCPError) -> String {
  Json::object({
    "jsonrpc": "2.0",
    "id": id.to_json(),
    "error": err.to_jsonrpc_error(),
  }).stringify()
}

///|
/// Extract a request's `params._meta` object, or `None` when `params` is not
/// an object or its `_meta` is absent/non-object.
fn request_meta(params : Json) -> Map[String, Json]? {
  if params is Object(obj) {
    match obj.get("_meta") {
      Some(Object(meta)) => Some(meta)
      _ => None
    }
  } else {
    None
  }
}

///|
/// Extract the protocol version declared in a request's `params._meta`.
/// Returns `Some(requested_version)` when the field is present as a string,
/// `None` when it is missing or non-string. The field is required on every
/// request (spec basic/index#_meta): `check_protocol_version` rejects a
/// missing/non-string value with -32602 before the mismatch check applies.
fn extract_protocol_version(params : Json) -> String? {
  match request_meta(params) {
    Some(meta) =>
      match meta.get("io.modelcontextprotocol/protocolVersion") {
        Some(String(v)) => Some(v)
        _ => None
      }
    None => None
  }
}

///|
/// JSON-RPC -32602 "Invalid params" response for a request missing one of
/// the `params._meta` fields the spec makes mandatory on every request.
fn missing_meta_field_error(id : @types.RequestId, field : String) -> String {
  jsonrpc_error_str(id, -32602, "Missing required _meta field: " + field)
}

///|
/// Validate a request's `params._meta` at the request entry point (spec
/// basic/index#_meta): every request MUST carry
/// `io.modelcontextprotocol/protocolVersion` (string) and
/// `io.modelcontextprotocol/clientCapabilities` (object). A missing or
/// wrongly-typed field makes the params malformed → -32602. A present-but-
/// unsupported version keeps the existing -32022 `UnsupportedProtocolVersion`
/// error (with supported/requested data); that check runs before the
/// clientCapabilities presence check so version-mismatched legacy requests
/// still get the version signal. Returns `None` when the request passes.
///
/// Called by both request entry points — `handle_parsed_request` (public
/// `handle_request`) and `handle_server_request` (stdio/HTTP, including
/// `subscriptions/listen`) — before method routing. Notifications never
/// reach this check: they are routed to `handle_inbound_notification`.
fn check_protocol_version(id : @types.RequestId, params : Json) -> String? {
  match request_meta(params) {
    None =>
      Some(
        missing_meta_field_error(id, "io.modelcontextprotocol/protocolVersion"),
      )
    Some(meta) =>
      match extract_protocol_version(params) {
        None =>
          Some(
            missing_meta_field_error(
              id, "io.modelcontextprotocol/protocolVersion",
            ),
          )
        Some(version) =>
          if version != @types.ProtocolVersion {
            Some(
              jsonrpc_error_from(
                id,
                @types.UnsupportedProtocolVersion(
                  "Unsupported protocol version",
                  supported=[@types.ProtocolVersion],
                  requested=version,
                ),
              ),
            )
          } else {
            match meta.get("io.modelcontextprotocol/clientCapabilities") {
              Some(value) => {
                ignore(@types.ClientCapabilities::from_json(value)) catch {
                  error => return Some(jsonrpc_error_from(id, error))
                }
                match meta.get("progressToken") {
                  Some(token) =>
                    ignore(@types.ProgressToken::from_json(token)) catch {
                      error => return Some(jsonrpc_error_from(id, error))
                    }
                  None => ()
                }
                None
              }
              _ =>
                Some(
                  missing_meta_field_error(
                    id, "io.modelcontextprotocol/clientCapabilities",
                  ),
                )
            }
          }
      }
  }
}

///|
/// Check per-request capabilities, including sampling tools and elicitation mode.
fn check_required_capabilities(
  params : Json,
  input_requests : Map[String, @types.InputRequestEntry],
) -> @types.MCPError? {
  let meta = request_meta(params).unwrap_or({})
  let capabilities = @types.ClientCapabilities::from_json(
    meta.get("io.modelcontextprotocol/clientCapabilities").unwrap_or({}),
  ) catch {
    error => return Some(error)
  }
  let missing : Map[String, Json] = Map([])
  for key, entry in input_requests {
    validate_generated_input(entry) catch {
      error =>
        return Some(
          @types.InternalError(
            "Invalid server input request '" + key + "': \{Repr(error)}",
          ),
        )
    }
    match entry.method_name {
      @types.RootsList =>
        if capabilities.roots is None {
          missing.set("roots", {})
        }
      @types.ElicitationCreate => {
        let mode = if entry.params is { "mode": String("url"), .. } {
          "url"
        } else {
          "form"
        }
        let supported = match capabilities.elicitation {
          None => false
          Some(cap) =>
            if mode == "url" {
              cap.url is Some(_)
            } else {
              cap.form is Some(_) || cap.url is None
            }
        }
        if !supported {
          let required = match missing.get("elicitation") {
            Some(Object(fields)) => fields
            _ => {}
          }
          required.set(mode, {})
          missing.set("elicitation", Json::object(required))
        }
      }
      @types.SamplingCreateMessage => {
        let needs_tools = entry.params is Object(fields) &&
          (fields.contains("tools") || fields.contains("toolChoice"))
        let supported = match capabilities.sampling {
          None => false
          Some(cap) => !needs_tools || cap.tools is Some(_)
        }
        if !supported {
          missing.set(
            "sampling",
            if needs_tools {
              { "tools": {} }
            } else {
              {}
            },
          )
        }
      }
    }
  }
  if missing.is_empty() {
    None
  } else {
    let required = @types.ClientCapabilities::from_json(Json::object(missing)) catch {
      error => return Some(error)
    }
    Some(
      @types.MissingRequiredClientCapability(
        "Client did not declare required capability",
        required~,
      ),
    )
  }
}

///|
/// Handle `server/discover` — required by the 2026-07-28 spec. Returns the
/// protocol versions this server supports, its capabilities, and optional
/// instructions. Server identity is injected into `_meta` by
/// `with_server_meta` (per spec, `serverInfo` lives in `_meta`, not at the
/// result top level).
fn handle_discover(server : MCPServer, id : @types.RequestId) -> String {
  let result : Map[String, Json] = Default::default()
  result.set(
    "supportedVersions",
    Json::array([Json::string(@types.ProtocolVersion)]),
  )
  result.set("capabilities", server.capabilities().to_json())
  match server.instructions {
    Some(instr) => result.set("instructions", Json::string(instr))
    None => ()
  }
  jsonrpc_cacheable_success_str(
    server,
    id,
    Json::object(result),
    3600000,
    "public",
  )
}

///|
fn extract_json_string(json : Json, field : String) -> String? {
  if json is Object(obj) {
    match obj.get(field) {
      Some(String(s)) => Some(s)
      _ => None
    }
  } else {
    None
  }
}

///|
/// Verify retry state before exposing any client input to business handlers.
fn restore_request_context(
  server : MCPServer,
  context : @runtime.RequestContext,
  method_name : String,
  params : Json,
  salient_params : Json,
) -> @runtime.RequestContext raise @types.MCPError {
  guard params is Object(fields) else {
    raise @types.InvalidParams("Request params must be an object")
  }
  let responses = match fields.get("inputResponses") {
    None => Map([])
    Some(Object(responses)) => responses.copy()
    Some(_) => raise @types.InvalidParams("inputResponses must be an object")
  }
  let state = match fields.get("requestState") {
    None => {
      for _, response in responses {
        @validation.check_unbound_input_response(response)
      }
      None
    }
    Some(String(blob)) => {
      let codec = match server.request_state_codec {
        Some(codec) => codec
        None =>
          raise @types.InvalidParams(
            "requestState is not enabled on this server",
          )
      }
      let payload = codec.open(
        blob,
        {
          principal: context.principal.map(fn(p) { p.id }),
          request_method: method_name,
          params: salient_params,
        },
        now=(server.clock)(),
      )
      match payload {
        Some(payload) => Some(restore_input_state(payload.state, responses))
        None => raise @types.InvalidParams("requestState verification failed")
      }
    }
    Some(_) => raise @types.InvalidParams("requestState must be a string")
  }
  { ..context, input_responses: responses, continuation_state: state, }
}

///|
fn seal_request_state(
  server : MCPServer,
  context : @runtime.RequestContext,
  method_name : String,
  salient_params : Json,
  state : Json,
  input_requests : Map[String, @types.InputRequestEntry],
) -> String raise @types.MCPError {
  let codec = match server.request_state_codec {
    Some(codec) => codec
    None =>
      raise @types.InternalError(
        "Handler requested client input but server has no requestState codec",
      )
  }
  let now = (server.clock)()
  codec.seal(
    {
      principal: context.principal.map(fn(p) { p.id }),
      expires_at: now + 300,
      request_method: method_name,
      params_digest: params_digest(salient_params),
      state: sealed_input_state(state, input_requests),
    },
    now~,
  )
}

///|
fn handle_tools_list(server : MCPServer, id : @types.RequestId) -> String {
  let tools = server.registry.list_tools()
  let tool_jsons = tools.map(@types.ToolDefinition::to_json)
  jsonrpc_cacheable_success_str(
    server,
    id,
    Json::object({ "tools": Json::array(tool_jsons) }),
    60000,
    "public",
  )
}

///|
/// Serialize through the shared wire codec, including structured output and metadata.
fn tool_result_to_json(tool_result : @tool.ToolResult) -> Json {
  tool_result.to_json()
}

///|
async fn handle_tools_call(
  server : MCPServer,
  context : @runtime.RequestContext,
  params : Json,
) -> String {
  let id = context.request_id
  let name = match extract_json_string(params, "name") {
    Some(name) => name
    None => return jsonrpc_error_str(id, -32602, "Missing 'name' parameter")
  }
  let arguments = match params {
    Object(fields) => fields.get("arguments").unwrap_or(Json::object({}))
    _ =>
      return jsonrpc_error_str(id, -32602, "Request params must be an object")
  }
  guard arguments is Object(_) else {
    return jsonrpc_error_str(id, -32602, "Tool arguments must be an object")
  }
  let salient_params = Json::object({
    "name": Json::string(name),
    "arguments": arguments,
  })
  let context = restore_request_context(
    server, context, "tools/call", params, salient_params,
  ) catch {
    error => return jsonrpc_error_from(id, error)
  }
  let outcome = server.registry.call_tool(name, context, arguments)
  context.cancellation_token.throw_if_cancelled()
  match outcome {
    Ok(@tool.Complete(tool_result)) => {
      let result = tool_result_to_json(tool_result)
      ignore(@types.ToolResult::from_json(result)) catch {
        _ =>
          return jsonrpc_error_str(
            id, -32603, "Handler returned an invalid tool result",
          )
      }
      jsonrpc_success_str(server, id, result)
    }
    Ok(@tool.InputRequired(input_requests~, state~)) => {
      match check_required_capabilities(params, input_requests) {
        Some(error) => return jsonrpc_error_from(id, error)
        None => ()
      }
      let blob = seal_request_state(
        server, context, "tools/call", salient_params, state, input_requests,
      ) catch {
        error => return jsonrpc_error_from(id, error)
      }
      jsonrpc_input_required_str(
        server,
        id,
        input_requests,
        request_state=Some(blob),
      )
    }
    Err(error) => jsonrpc_error_from(id, error)
  }
}

///|
fn handle_resources_list(server : MCPServer, id : @types.RequestId) -> String {
  let resources = server.resource_registry.list_resources()
  let resource_jsons = resources.map(@types.ResourceDefinition::to_json)
  jsonrpc_cacheable_success_str(
    server,
    id,
    Json::object({ "resources": Json::array(resource_jsons) }),
    60000,
    "public",
  )
}

///|
fn handle_resources_templates_list(
  server : MCPServer,
  id : @types.RequestId,
) -> String {
  let templates = server.resource_registry.list_templates()
  let template_jsons = templates.map(@types.ResourceTemplateDefinition::to_json)
  jsonrpc_cacheable_success_str(
    server,
    id,
    Json::object({ "resourceTemplates": Json::array(template_jsons) }),
    60000,
    "public",
  )
}

///|
async fn handle_resources_read(
  server : MCPServer,
  context : @runtime.RequestContext,
  params : Json,
) -> String {
  let id = context.request_id
  let uri = match extract_json_string(params, "uri") {
    Some(uri) => uri
    None => return jsonrpc_error_str(id, -32602, "Missing 'uri' parameter")
  }
  let salient_params = Json::object({ "uri": Json::string(uri) })
  let context = restore_request_context(
    server, context, "resources/read", params, salient_params,
  ) catch {
    error => return jsonrpc_error_from(id, error)
  }
  let outcome = server.resource_registry.read_resource(
    uri, context, salient_params,
  )
  context.cancellation_token.throw_if_cancelled()
  match outcome {
    Ok(@resource.Complete(result)) => {
      let result = result.to_json()
      ignore(@types.ResourceReadResult::from_json(result)) catch {
        _ =>
          return jsonrpc_error_str(
            id, -32603, "Handler returned an invalid resource result",
          )
      }
      jsonrpc_cacheable_success_str(server, id, result, 30000, "private")
    }
    Ok(@resource.InputRequired(input_requests~, state~)) => {
      match check_required_capabilities(params, input_requests) {
        Some(error) => return jsonrpc_error_from(id, error)
        None => ()
      }
      let blob = seal_request_state(
        server, context, "resources/read", salient_params, state, input_requests,
      ) catch {
        error => return jsonrpc_error_from(id, error)
      }
      jsonrpc_input_required_str(
        server,
        id,
        input_requests,
        request_state=Some(blob),
      )
    }
    Err(error) => jsonrpc_error_from(id, error)
  }
}

///|
fn handle_prompts_list(server : MCPServer, id : @types.RequestId) -> String {
  let prompts = server.prompt_registry.list_prompts()
  let prompt_jsons = prompts.map(@types.PromptDefinition::to_json)
  jsonrpc_cacheable_success_str(
    server,
    id,
    Json::object({ "prompts": Json::array(prompt_jsons) }),
    60000,
    "public",
  )
}

///|
async fn handle_prompts_get(
  server : MCPServer,
  context : @runtime.RequestContext,
  params : Json,
) -> String {
  let id = context.request_id
  let name = match extract_json_string(params, "name") {
    Some(name) => name
    None => return jsonrpc_error_str(id, -32602, "Missing 'name' parameter")
  }
  let arguments = match params {
    Object(fields) => fields.get("arguments").unwrap_or(Json::object({}))
    _ =>
      return jsonrpc_error_str(id, -32602, "Request params must be an object")
  }
  guard arguments is Object(_) else {
    return jsonrpc_error_str(id, -32602, "Prompt arguments must be an object")
  }
  let salient_params = Json::object({
    "name": Json::string(name),
    "arguments": arguments,
  })
  let context = restore_request_context(
    server, context, "prompts/get", params, salient_params,
  ) catch {
    error => return jsonrpc_error_from(id, error)
  }
  let outcome = server.prompt_registry.get_prompt(name, context, arguments)
  context.cancellation_token.throw_if_cancelled()
  match outcome {
    Ok(@prompt.Complete(result)) => {
      let result = result.to_json()
      ignore(@types.GetPromptResult::from_json(result)) catch {
        _ =>
          return jsonrpc_error_str(
            id, -32603, "Handler returned an invalid prompt result",
          )
      }
      jsonrpc_success_str(server, id, result)
    }
    Ok(@prompt.InputRequired(input_requests~, state~)) => {
      match check_required_capabilities(params, input_requests) {
        Some(error) => return jsonrpc_error_from(id, error)
        None => ()
      }
      let blob = seal_request_state(
        server, context, "prompts/get", salient_params, state, input_requests,
      ) catch {
        error => return jsonrpc_error_from(id, error)
      }
      jsonrpc_input_required_str(
        server,
        id,
        input_requests,
        request_state=Some(blob),
      )
    }
    Err(error) => jsonrpc_error_from(id, error)
  }
}
