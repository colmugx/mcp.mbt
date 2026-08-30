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
      obj.set("resultType", Json::string("complete"))
      obj.set(
        "_meta",
        Json::object({
          "io.modelcontextprotocol/serverInfo": server_info_meta(server),
        }),
      )
      result
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
  // with_server_meta injects resultType + _meta by mutating result in place
  // (when it is an Object); add the cache fields to the same object.
  match with_server_meta(server, result) {
    Object(obj) => {
      obj.set("ttlMs", Json::number(ttl_ms.to_double()))
      obj.set("cacheScope", Json::string(cache_scope))
      ()
    }
    _ => ()
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": request_id_to_json(id),
    "result": result,
  }).stringify()
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
  jsonrpc_error_str(
    id,
    err.to_error_code(),
    err.message(),
    data=err.to_error_data(),
  )
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
              Some(Object(_)) => None
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
/// Extract the set of client capabilities declared in a request's
/// `params._meta.io.modelcontextprotocol/clientCapabilities`. Keys that are
/// present in the object count as declared; the value is ignored. A missing or
/// malformed field is treated as an empty capability set (presence itself is
/// enforced by `check_protocol_version`).
fn extract_client_capabilities(params : Json) -> Map[String, Unit] {
  let caps : Map[String, Unit] = Default::default()
  match request_meta(params) {
    Some(meta) =>
      match meta.get("io.modelcontextprotocol/clientCapabilities") {
        Some(Object(caps_obj)) => caps_obj.each(fn(k, _) { caps.set(k, ()) })
        _ => ()
      }
    None => ()
  }
  caps
}

///|
/// Map an `InputRequestKind` to the client-capability key that authorizes the
/// server to include it in `inputRequests`.
fn capability_for_input_request(kind : @types.InputRequestKind) -> String {
  match kind {
    @types.ElicitationCreate => "elicitation"
    @types.SamplingCreateMessage => "sampling"
    @types.RootsList => "roots"
  }
}

///|
/// Validate that every `inputRequests` entry corresponds to a capability the
/// client declared in `params._meta.clientCapabilities`. Returns the first
/// `MissingRequiredClientCapability` error when any are missing; `None`
/// otherwise.
fn check_required_capabilities(
  params : Json,
  input_requests : Map[String, @types.InputRequestEntry],
) -> @types.MCPError? {
  let caps = extract_client_capabilities(params)
  let missing : Array[String] = []
  input_requests.each(fn(_key, entry) {
    let cap = capability_for_input_request(entry.method_name)
    if !caps.contains(cap) {
      missing.push(cap)
    }
  })
  if missing.is_empty() {
    None
  } else {
    Some(
      @types.MissingRequiredClientCapability(
        "Client did not declare required capability",
        required=missing,
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
  result.set(
    "capabilities",
    Json::object({
      "tools": { "listChanged": true },
      "resources": { "listChanged": true },
      "prompts": { "listChanged": true },
    }),
  )
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
/// Extract the echoed `requestState` blob from a retry request's params.
/// Presence indicates this is an MRTR retry (not an initial request).
fn extract_request_state(params : Json) -> String? {
  if params is Object(obj) {
    match obj.get("requestState") {
      Some(String(s)) => Some(s)
      _ => None
    }
  } else {
    None
  }
}

///|
/// Extract `inputResponses` from a retry request's params as a map of
/// server-key → client result JSON. Returns None if absent (initial request).
fn extract_input_responses(params : Json) -> Map[String, Json]? {
  if params is Object(obj) {
    match obj.get("inputResponses") {
      Some(Object(responses)) => {
        let out : Map[String, Json] = Default::default()
        responses.each(fn(k, v) { out.set(k, v) })
        Some(out)
      }
      _ => None
    }
  } else {
    None
  }
}

///|
/// Merge a retry's `inputResponses` into the tool arguments under
/// `_mrtr_responses`, so a tool resuming after input_required reads its
/// fulfilled inputs from one place. Non-object arguments are wrapped.
fn merge_input_responses(
  arguments : Json,
  responses : Map[String, Json]?,
) -> Json {
  let merged : Map[String, Json] = match arguments {
    Object(obj) => obj
    _ => Default::default()
  }
  match responses {
    Some(r) => merged.set("_mrtr_responses", Json::object(r))
    None => ()
  }
  Json::object(merged)
}

///|
fn handle_tools_list(server : MCPServer, id : @types.RequestId) -> String {
  let tools = server.registry.list_tools()
  let tool_jsons = tools.map(fn(tool) {
    Json::object({
      "name": tool.name,
      "description": tool.description,
      "inputSchema": tool.input_schema,
    })
  })
  jsonrpc_cacheable_success_str(
    server,
    id,
    Json::object({ "tools": Json::array(tool_jsons) }),
    60000,
    "public",
  )
}

///|
/// Serialize one `@types.ContentItem` to its wire shape. Embedded resources
/// use the nested form the spec requires — `{type:"resource", resource:{uri,
/// text|blob, mimeType?}}` — matching the client's `serialize_content_item`
/// (the flat `{type:"resource", uri, ...}` layout is not spec-conformant).
/// Shared by `tools/call` and `prompts/get` results.
fn content_item_to_json(item : @types.ContentItem) -> Json {
  match item {
    @types.Text(text) =>
      Json::object({ "type": Json::string("text"), "text": Json::string(text) })
    @types.Image(data, mime_type~) =>
      Json::object({
        "type": Json::string("image"),
        "data": Json::string(data),
        "mimeType": Json::string(mime_type),
      })
    @types.ResourceLink(uri) =>
      Json::object({
        "type": Json::string("resource_link"),
        "uri": Json::string(uri),
      })
    @types.EmbeddedResource(content) =>
      match content {
        @types.Text(text, uri~, mime_type~) => {
          let res : Map[String, Json] = Default::default()
          res.set("uri", Json::string(uri))
          res.set("text", Json::string(text))
          match mime_type {
            Some(mt) => res.set("mimeType", Json::string(mt))
            None => ()
          }
          Json::object({
            "type": Json::string("resource"),
            "resource": Json::object(res),
          })
        }
        @types.Blob(data, uri~, mime_type~) =>
          Json::object({
            "type": Json::string("resource"),
            "resource": Json::object({
              "uri": Json::string(uri),
              "blob": Json::string(data),
              "mimeType": Json::string(mime_type),
            }),
          })
      }
  }
}

///|
/// Serialize a `ToolResult` into the JSON object shape used in `tools/call`
/// responses (`{ content: [...], isError: bool }`).
fn tool_result_to_json(tool_result : @tool.ToolResult) -> Json {
  Json::object({
    "content": Json::array(tool_result.content.map(content_item_to_json)),
    "isError": Json::boolean(tool_result.is_error),
  })
}

///|
async fn handle_tools_call(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let tool_name = extract_json_string(params, "name")
  match tool_name {
    None => jsonrpc_error_str(id, -32602, "Missing 'name' parameter")
    Some(name) => {
      let arguments = if params is Object(obj) {
        obj.get("arguments").unwrap_or(null)
      } else {
        null
      }
      // MRTR retry: the client echoes `requestState` from a previous
      // input_required response. Verify it (principal/method/params/expiry)
      // and expose `inputResponses` to the tool via `_mrtr_responses` in the
      // arguments. A present-but-invalid blob is rejected, not retried.
      let arguments = match extract_request_state(params) {
        Some(blob) => {
          let codec = match server.request_state_codec {
            Some(c) => c
            None =>
              return jsonrpc_error_str(
                id, -32603, "Retry carried requestState but server has no codec",
              )
          }
          let payload = match
            codec.open(
              blob,
              {
                principal: None,
                request_method: "tools/call",
                params: arguments,
              },
              now=(server.clock)(),
            ) {
            Some(p) => p
            None =>
              return jsonrpc_error_str(
                id, -32020, "requestState verification failed",
              )
          }
          ignore(payload)
          merge_input_responses(arguments, extract_input_responses(params))
        }
        None => arguments
      }
      match server.registry.call_tool(name, arguments) {
        Ok(@tool.Complete(tool_result)) => {
          let result = tool_result_to_json(tool_result)
          jsonrpc_success_str(server, id, result)
        }
        Ok(@tool.InputRequired(input_requests~, state~)) =>
          // Tool requested client input via MRTR. First enforce capability
          // gating: the server MUST NOT ask for inputs the client did not
          // declare support for.
          match check_required_capabilities(params, input_requests) {
            Some(err) => jsonrpc_error_from(id, err)
            None =>
              // Seal the continuation state into requestState if a codec is
              // configured; otherwise we cannot safely round-trip state.
              match server.request_state_codec {
                Some(codec) => {
                  let now = (server.clock)()
                  let payload : RequestStatePayload = {
                    principal: None,
                    expires_at: now + 300,
                    request_method: "tools/call",
                    params_digest: params_digest(arguments),
                    state,
                  }
                  let blob = codec.seal(payload, now~)
                  jsonrpc_input_required_str(
                    server,
                    id,
                    input_requests,
                    request_state=Some(blob),
                  )
                }
                None =>
                  jsonrpc_error_str(
                    id, -32603, "Tool requested client input but server has no requestState codec",
                  )
              }
          }
        Err(e) => jsonrpc_error_from(id, e)
      }
    }
  }
}

///|
fn handle_resources_list(server : MCPServer, id : @types.RequestId) -> String {
  let resources = server.resource_registry.list_resources()
  let resource_jsons = resources.map(fn(resource) {
    let map : Map[String, Json] = Default::default()
    map.set("uri", Json::string(resource.uri))
    map.set("name", Json::string(resource.name))
    match resource.description {
      Some(desc) => map.set("description", Json::string(desc))
      None => ()
    }
    match resource.mime_type {
      Some(mt) => map.set("mimeType", Json::string(mt))
      None => ()
    }
    Json::object(map)
  })
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
  let template_jsons = templates.map(fn(template) {
    let map : Map[String, Json] = Default::default()
    map.set("uriTemplate", Json::string(template.uri_template))
    map.set("name", Json::string(template.name))
    match template.description {
      Some(desc) => map.set("description", Json::string(desc))
      None => ()
    }
    match template.mime_type {
      Some(mt) => map.set("mimeType", Json::string(mt))
      None => ()
    }
    Json::object(map)
  })
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
  id : @types.RequestId,
  params : Json,
) -> String {
  let uri = extract_json_string(params, "uri")
  match uri {
    None => jsonrpc_error_str(id, -32602, "Missing 'uri' parameter")
    Some(uri_str) => {
      let salient_params = Json::object({ "uri": Json::string(uri_str) })
      // MRTR retry: the client echoes `requestState` and may provide
      // `inputResponses`. Verify the blob and expose responses to the handler
      // via `_mrtr_responses` in the read params.
      let handler_params = match extract_request_state(params) {
        Some(blob) => {
          let codec = match server.request_state_codec {
            Some(c) => c
            None =>
              return jsonrpc_error_str(
                id, -32603, "Retry carried requestState but server has no codec",
              )
          }
          let _payload = match
            codec.open(
              blob,
              {
                principal: None,
                request_method: "resources/read",
                params: salient_params,
              },
              now=(server.clock)(),
            ) {
            Some(p) => p
            None =>
              return jsonrpc_error_str(
                id, -32020, "requestState verification failed",
              )
          }
          merge_input_responses(params, extract_input_responses(params))
        }
        None => params
      }
      match server.resource_registry.read_resource(uri_str, handler_params) {
        Ok(@resource.Complete(read_result)) => {
          let content_json = match read_result.content {
            @resource.Text(text) =>
              Json::object({ "uri": read_result.uri, "text": text })
            @resource.Blob(data, mime_type~) =>
              Json::object({
                "uri": read_result.uri,
                "blob": data.to_string(),
                "mimeType": mime_type,
              })
          }
          jsonrpc_cacheable_success_str(
            server,
            id,
            Json::object({ "contents": Json::array([content_json]) }),
            30000,
            "private",
          )
        }
        Ok(@resource.InputRequired(input_requests~, state~)) =>
          match check_required_capabilities(params, input_requests) {
            Some(err) => jsonrpc_error_from(id, err)
            None =>
              match server.request_state_codec {
                Some(codec) => {
                  let now = (server.clock)()
                  let payload : RequestStatePayload = {
                    principal: None,
                    expires_at: now + 300,
                    request_method: "resources/read",
                    params_digest: params_digest(salient_params),
                    state,
                  }
                  let blob = codec.seal(payload, now~)
                  jsonrpc_input_required_str(
                    server,
                    id,
                    input_requests,
                    request_state=Some(blob),
                  )
                }
                None =>
                  jsonrpc_error_str(
                    id, -32603, "Resource requested client input but server has no requestState codec",
                  )
              }
          }
        Err(e) => jsonrpc_error_from(id, e)
      }
    }
  }
}

///|
fn handle_prompts_list(server : MCPServer, id : @types.RequestId) -> String {
  let prompts = server.prompt_registry.list_prompts()
  let prompt_jsons = prompts.map(fn(prompt) {
    let map : Map[String, Json] = Default::default()
    map.set("name", Json::string(prompt.name))
    match prompt.description {
      Some(desc) => map.set("description", Json::string(desc))
      None => ()
    }
    match prompt.arguments {
      Some(args) => {
        let arg_jsons = args.map(fn(arg) {
          let arg_map : Map[String, Json] = Default::default()
          arg_map.set("name", Json::string(arg.name))
          match arg.description {
            Some(d) => arg_map.set("description", Json::string(d))
            None => ()
          }
          match arg.required {
            Some(true) => arg_map.set("required", true)
            _ => ()
          }
          Json::object(arg_map)
        })
        map.set("arguments", Json::array(arg_jsons))
      }
      None => ()
    }
    Json::object(map)
  })
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
  id : @types.RequestId,
  params : Json,
) -> String {
  let prompt_name = extract_json_string(params, "name")
  match prompt_name {
    None => jsonrpc_error_str(id, -32602, "Missing 'name' parameter")
    Some(name) => {
      let arguments = if params is Object(obj) {
        obj.get("arguments").unwrap_or(null)
      } else {
        null
      }
      let salient_params = Json::object({
        "name": Json::string(name),
        "arguments": arguments,
      })
      // MRTR retry: verify `requestState` and merge `inputResponses` into the
      // get params under `_mrtr_responses`.
      let handler_params = match extract_request_state(params) {
        Some(blob) => {
          let codec = match server.request_state_codec {
            Some(c) => c
            None =>
              return jsonrpc_error_str(
                id, -32603, "Retry carried requestState but server has no codec",
              )
          }
          let _payload = match
            codec.open(
              blob,
              {
                principal: None,
                request_method: "prompts/get",
                params: salient_params,
              },
              now=(server.clock)(),
            ) {
            Some(p) => p
            None =>
              return jsonrpc_error_str(
                id, -32020, "requestState verification failed",
              )
          }
          merge_input_responses(params, extract_input_responses(params))
        }
        None => params
      }
      match server.prompt_registry.get_prompt(name, handler_params) {
        Ok(@prompt.Complete(prompt_result)) => {
          let messages_json = prompt_result.messages.map(fn(msg) {
            Json::object({
              "role": msg.role,
              "content": content_item_to_json(msg.content),
            })
          })
          let result_map : Map[String, Json] = Default::default()
          match prompt_result.description {
            Some(d) => result_map.set("description", Json::string(d))
            None => ()
          }
          result_map.set("messages", Json::array(messages_json))
          jsonrpc_success_str(server, id, Json::object(result_map))
        }
        Ok(@prompt.InputRequired(input_requests~, state~)) =>
          match check_required_capabilities(params, input_requests) {
            Some(err) => jsonrpc_error_from(id, err)
            None =>
              match server.request_state_codec {
                Some(codec) => {
                  let now = (server.clock)()
                  let payload : RequestStatePayload = {
                    principal: None,
                    expires_at: now + 300,
                    request_method: "prompts/get",
                    params_digest: params_digest(salient_params),
                    state,
                  }
                  let blob = codec.seal(payload, now~)
                  jsonrpc_input_required_str(
                    server,
                    id,
                    input_requests,
                    request_state=Some(blob),
                  )
                }
                None =>
                  jsonrpc_error_str(
                    id, -32603, "Prompt requested client input but server has no requestState codec",
                  )
              }
          }
        Err(e) => jsonrpc_error_from(id, e)
      }
    }
  }
}
