///|
fn client_capabilities_to_json(
  capabilities : @types.ClientCapabilities,
) -> Json {
  let caps_map : Map[String, Json] = Default::default()
  match capabilities.roots {
    Some(roots_cap) =>
      caps_map.set("roots", { "listChanged": roots_cap.list_changed })
    None => ()
  }
  match capabilities.sampling {
    Some(_) => caps_map.set("sampling", {})
    None => ()
  }
  match capabilities.elicitation {
    Some(_) => caps_map.set("elicitation", { "form": {} })
    None => ()
  }
  Json::object(caps_map)
}

///|
/// Build the `_meta` object every modern request carries in its `params`.
/// Contains the required `io.modelcontextprotocol/protocolVersion` and
/// `clientCapabilities`, plus the recommended `clientInfo`. An optional
/// `logLevel` mirrors the legacy `logging/setLevel` RPC into per-request
/// metadata (per spec, `logging/setLevel` is removed).
fn build_request_meta(
  client_name : String,
  client_version : String,
  capabilities : @types.ClientCapabilities,
  log_level? : String? = None,
) -> Json {
  let meta : Map[String, Json] = Default::default()
  meta.set(
    "io.modelcontextprotocol/protocolVersion",
    Json::string(@types.ProtocolVersion),
  )
  meta.set(
    "io.modelcontextprotocol/clientCapabilities",
    client_capabilities_to_json(capabilities),
  )
  meta.set("io.modelcontextprotocol/clientInfo", {
    "name": client_name,
    "version": client_version,
  })
  match log_level {
    Some(level) =>
      meta.set("io.modelcontextprotocol/logLevel", Json::string(level))
    None => ()
  }
  Json::object(meta)
}

///|
fn build_tools_list_request(
  id : Int,
  meta : Json,
  cursor? : String = "",
) -> String {
  let params : Map[String, Json] = Default::default()
  params.set("_meta", meta)
  if cursor != "" {
    params.set("cursor", Json::string(cursor))
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "tools/list",
    "params": Json::object(params),
  }).stringify()
}

///|
fn build_tools_call_request(
  id : Int,
  name : String,
  meta : Json,
  arguments? : String = "{}",
  progress_token? : String = "",
) -> String {
  let arguments_json = @json.parse(arguments) catch { _ => Json::object({}) }
  let params_map : Map[String, Json] = Default::default()
  params_map.set("name", Json::string(name))
  params_map.set("arguments", arguments_json)
  // Merge progressToken into the request _meta alongside protocol-level fields.
  match meta {
    Object(obj) => {
      if progress_token != "" {
        obj.set("progressToken", Json::string(progress_token))
      }
      params_map.set("_meta", meta)
    }
    _ => params_map.set("_meta", meta)
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "tools/call",
    "params": Json::object(params_map),
  }).stringify()
}

///|
fn build_resources_list_request(
  id : Int,
  meta : Json,
  cursor? : String = "",
) -> String {
  let params : Map[String, Json] = Default::default()
  params.set("_meta", meta)
  if cursor != "" {
    params.set("cursor", Json::string(cursor))
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "resources/list",
    "params": Json::object(params),
  }).stringify()
}

///|
fn build_resources_read_request(id : Int, uri : String, meta : Json) -> String {
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "resources/read",
    "params": { "uri": uri, "_meta": meta },
  }).stringify()
}

///|
fn build_prompts_list_request(
  id : Int,
  meta : Json,
  cursor? : String = "",
) -> String {
  let params : Map[String, Json] = Default::default()
  params.set("_meta", meta)
  if cursor != "" {
    params.set("cursor", Json::string(cursor))
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "prompts/list",
    "params": Json::object(params),
  }).stringify()
}

///|
fn build_prompts_get_request(
  id : Int,
  name : String,
  meta : Json,
  arguments? : String = "{}",
) -> String {
  let arguments_json = @json.parse(arguments) catch { _ => Json::object({}) }
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "prompts/get",
    "params": { "name": name, "arguments": arguments_json, "_meta": meta },
  }).stringify()
}

///|
fn build_resources_templates_list_request(
  id : Int,
  meta : Json,
  cursor? : String = "",
) -> String {
  let params : Map[String, Json] = Default::default()
  params.set("_meta", meta)
  if cursor != "" {
    params.set("cursor", Json::string(cursor))
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "resources/templates/list",
    "params": Json::object(params),
  }).stringify()
}

///|
fn build_completion_complete_request(
  id : Int,
  meta : Json,
  ref_type~ : String,
  ref_name~ : String,
  argument_name~ : String,
  argument_value~ : String,
) -> String {
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "completion/complete",
    "params": {
      "ref": { "type": ref_type, "name": ref_name },
      "argument": { "name": argument_name, "value": argument_value },
      "_meta": meta,
    },
  }).stringify()
}

///|
/// Build a `server/discover` request. Per the 2026-07-28 spec the request
/// carries no parameters beyond the standard `_meta`; it is the primary way
/// clients learn a server's supported versions, capabilities, and identity,
/// and serves as the era probe for legacy fallback.
fn build_discover_request(id : Int, meta : Json) -> String {
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "server/discover",
    "params": { "_meta": meta },
  }).stringify()
}
