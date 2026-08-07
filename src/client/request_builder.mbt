///|
fn client_capabilities_to_json(
  capabilities : @types.ClientCapabilities,
) -> Json {
  let caps_map : Map[String, Json] = Default::default()
  match capabilities.roots {
    Some(roots_cap) =>
      caps_map.set(
        "roots",
        Json::object({ "listChanged": Json::boolean(roots_cap.list_changed) }),
      )
    None => ()
  }
  match capabilities.sampling {
    Some(_) => caps_map.set("sampling", Json::object({}))
    None => ()
  }
  match capabilities.elicitation {
    Some(_) =>
      caps_map.set("elicitation", Json::object({ "form": Json::object({}) }))
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
  meta.set(
    "io.modelcontextprotocol/clientInfo",
    Json::object({
      "name": Json::string(client_name),
      "version": Json::string(client_version),
    }),
  )
  match log_level {
    Some(level) =>
      meta.set("io.modelcontextprotocol/logLevel", Json::string(level))
    None => ()
  }
  Json::object(meta)
}

///|
fn build_initialize_request(
  id : Int,
  client_name : String,
  client_version : String,
  capabilities~ : @types.ClientCapabilities,
) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("initialize"),
    "params": Json::object({
      "protocolVersion": Json::string("2025-11-25"),
      "capabilities": client_capabilities_to_json(capabilities),
      "clientInfo": Json::object({
        "name": Json::string(client_name),
        "version": Json::string(client_version),
      }),
    }),
  }).stringify()
}

///|
fn build_initialized_notification() -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/initialized"),
  }).stringify()
}

///|
fn build_ping_request(id : Int) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("ping"),
  }).stringify()
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
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("tools/list"),
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
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("tools/call"),
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
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("resources/list"),
    "params": Json::object(params),
  }).stringify()
}

///|
fn build_resources_read_request(id : Int, uri : String, meta : Json) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("resources/read"),
    "params": Json::object({ "uri": Json::string(uri), "_meta": meta }),
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
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("prompts/list"),
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
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("prompts/get"),
    "params": Json::object({
      "name": Json::string(name),
      "arguments": arguments_json,
      "_meta": meta,
    }),
  }).stringify()
}

///|
fn build_set_log_level_request(id : Int, level : String) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("logging/setLevel"),
    "params": Json::object({ "level": Json::string(level) }),
  }).stringify()
}

///|
fn build_resources_subscribe_request(id : Int, uri : String) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("resources/subscribe"),
    "params": Json::object({ "uri": Json::string(uri) }),
  }).stringify()
}

///|
fn build_resources_unsubscribe_request(id : Int, uri : String) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("resources/unsubscribe"),
    "params": Json::object({ "uri": Json::string(uri) }),
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
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("resources/templates/list"),
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
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("completion/complete"),
    "params": Json::object({
      "ref": Json::object({
        "type": Json::string(ref_type),
        "name": Json::string(ref_name),
      }),
      "argument": Json::object({
        "name": Json::string(argument_name),
        "value": Json::string(argument_value),
      }),
      "_meta": meta,
    }),
  }).stringify()
}
