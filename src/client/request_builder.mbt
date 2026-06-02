///|
pub fn build_initialize_request(
  id : Int,
  client_name : String,
  client_version : String,
  capabilities~ : @types.ClientCapabilities,
) -> String {
  let caps_map : Map[String, Json] = {}
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
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("initialize"),
    "params": Json::object({
      "protocolVersion": Json::string("2025-11-25"),
      "capabilities": Json::object(caps_map),
      "clientInfo": Json::object({
        "name": Json::string(client_name),
        "version": Json::string(client_version),
      }),
    }),
  }).stringify()
}

///|
pub fn build_initialized_notification() -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/initialized"),
  }).stringify()
}

///|
pub fn build_ping_request(id : Int) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("ping"),
  }).stringify()
}

///|
pub fn build_tools_list_request(id : Int, cursor? : String = "") -> String {
  if cursor == "" {
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(id.to_double()),
      "method": Json::string("tools/list"),
    }).stringify()
  } else {
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(id.to_double()),
      "method": Json::string("tools/list"),
      "params": Json::object({ "cursor": Json::string(cursor) }),
    }).stringify()
  }
}

///|
pub fn build_tools_call_request(
  id : Int,
  name : String,
  arguments? : String = "{}",
  progress_token? : String = "",
) -> String {
  let arguments_json = @json.parse(arguments) catch { _ => Json::object({}) }
  let params_map : Map[String, Json] = {}
  params_map.set("name", Json::string(name))
  params_map.set("arguments", arguments_json)
  if progress_token != "" {
    params_map.set(
      "_meta",
      Json::object({ "progressToken": Json::string(progress_token) }),
    )
  }
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("tools/call"),
    "params": Json::object(params_map),
  }).stringify()
}

///|
pub fn build_resources_list_request(id : Int, cursor? : String = "") -> String {
  if cursor == "" {
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(id.to_double()),
      "method": Json::string("resources/list"),
    }).stringify()
  } else {
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(id.to_double()),
      "method": Json::string("resources/list"),
      "params": Json::object({ "cursor": Json::string(cursor) }),
    }).stringify()
  }
}

///|
pub fn build_resources_read_request(id : Int, uri : String) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("resources/read"),
    "params": Json::object({ "uri": Json::string(uri) }),
  }).stringify()
}

///|
pub fn build_prompts_list_request(id : Int, cursor? : String = "") -> String {
  if cursor == "" {
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(id.to_double()),
      "method": Json::string("prompts/list"),
    }).stringify()
  } else {
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(id.to_double()),
      "method": Json::string("prompts/list"),
      "params": Json::object({ "cursor": Json::string(cursor) }),
    }).stringify()
  }
}

///|
pub fn build_prompts_get_request(
  id : Int,
  name : String,
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
    }),
  }).stringify()
}

///|
pub fn build_set_log_level_request(id : Int, level : String) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("logging/setLevel"),
    "params": Json::object({ "level": Json::string(level) }),
  }).stringify()
}

///|
pub fn build_resources_subscribe_request(id : Int, uri : String) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("resources/subscribe"),
    "params": Json::object({ "uri": Json::string(uri) }),
  }).stringify()
}

///|
pub fn build_resources_unsubscribe_request(id : Int, uri : String) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("resources/unsubscribe"),
    "params": Json::object({ "uri": Json::string(uri) }),
  }).stringify()
}

///|
pub fn build_resources_templates_list_request(
  id : Int,
  cursor? : String = "",
) -> String {
  if cursor == "" {
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(id.to_double()),
      "method": Json::string("resources/templates/list"),
    }).stringify()
  } else {
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(id.to_double()),
      "method": Json::string("resources/templates/list"),
      "params": Json::object({ "cursor": Json::string(cursor) }),
    }).stringify()
  }
}

///|
pub fn build_completion_complete_request(
  id : Int,
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
    }),
  }).stringify()
}
