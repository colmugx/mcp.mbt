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
fn server_info_meta(server : MCPServer) -> Json {
  let info : Map[String, Json] = Map([])
  info.set("name", Json::string(server.name))
  info.set("version", Json::string(server.version))
  match server.title {
    Some(t) => info.set("title", Json::string(t))
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
/// resources/list, resources/read, server/discover) per spec §F.
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
/// Serialize a `ToolResult` into the JSON object shape used in `tools/call`
/// responses (`{ content: [...], isError: bool }`).
fn tool_result_to_json(tool_result : @tool.ToolResult) -> Json {
  let content_items = tool_result.content.map(fn(item) {
    match item {
      @types.Text(text) =>
        Json::object({
          "type": Json::string("text"),
          "text": Json::string(text),
        })
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
            let map : Map[String, Json] = Default::default()
            map.set("type", Json::string("resource"))
            map.set("uri", Json::string(uri))
            map.set("text", Json::string(text))
            match mime_type {
              Some(mt) => map.set("mimeType", Json::string(mt))
              None => ()
            }
            Json::object(map)
          }
          @types.Blob(data, uri~, mime_type~) =>
            Json::object({
              "type": Json::string("resource"),
              "uri": Json::string(uri),
              "blob": Json::string(data),
              "mimeType": Json::string(mime_type),
            })
        }
    }
  })
  Json::object({
    "content": Json::array(content_items),
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
          // Tool requested client input via MRTR. Seal the continuation state
          // into requestState if a codec is configured; otherwise we cannot
          // safely round-trip state and must error.
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
async fn handle_resources_read(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let uri = extract_json_string(params, "uri")
  match uri {
    None => jsonrpc_error_str(id, -32602, "Missing 'uri' parameter")
    Some(uri_str) =>
      match server.resource_registry.read_resource(uri_str) {
        Ok(read_result) => {
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
        Err(e) => jsonrpc_error_from(id, e)
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
    Some(name) =>
      match server.prompt_registry.get_prompt(name, params) {
        Ok(prompt_result) => {
          let messages_json = prompt_result.messages.map(fn(msg) {
            let content = match msg.content {
              @types.Text(text) =>
                Json::object({ "type": "text", "text": text })
              _ => Json::null()
            }
            Json::object({ "role": msg.role, "content": content })
          })
          let result_map : Map[String, Json] = Default::default()
          match prompt_result.description {
            Some(d) => result_map.set("description", Json::string(d))
            None => ()
          }
          result_map.set("messages", Json::array(messages_json))
          jsonrpc_success_str(server, id, Json::object(result_map))
        }
        Err(e) => jsonrpc_error_from(id, e)
      }
  }
}
