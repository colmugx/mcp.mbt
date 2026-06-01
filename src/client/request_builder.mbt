///|
pub fn build_initialize_request(
  id : Int,
  client_name : String,
  client_version : String,
  capabilities~ : @types.ClientCapabilities,
) -> String {
  let client_info = @jsonutil.json_object([
    ("name", @jsonutil.json_string(client_name)),
    ("version", @jsonutil.json_string(client_version)),
  ])
  // Build capabilities JSON from struct
  let caps_pairs : Array[(String, String)] = []
  match capabilities.roots {
    Some(roots_cap) =>
      caps_pairs.push(
        (
          "roots",
          @jsonutil.json_object([
            ("listChanged", @jsonutil.json_bool(roots_cap.list_changed)),
          ]),
        ),
      )
    None => ()
  }
  match capabilities.sampling {
    Some(_) => caps_pairs.push(("sampling", @jsonutil.json_object([])))
    None => ()
  }
  match capabilities.elicitation {
    Some(elic) =>
      caps_pairs.push(
        (
          "elicitation",
          @jsonutil.json_object([("form", @jsonutil.json_bool(elic.form))]),
        ),
      )
    None => ()
  }
  let params = @jsonutil.json_object([
    ("protocolVersion", @jsonutil.json_string("2025-11-25")),
    ("capabilities", @jsonutil.json_object(caps_pairs)),
    ("clientInfo", client_info),
  ])
  @jsonutil.json_object([
    ("jsonrpc", @jsonutil.json_string("2.0")),
    ("id", @jsonutil.json_number(id)),
    ("method", @jsonutil.json_string("initialize")),
    ("params", params),
  ])
}

///|
pub fn build_initialized_notification() -> String {
  @jsonutil.jsonrpc_notification("notifications/initialized", None)
}

///|
pub fn build_ping_request(id : Int) -> String {
  @jsonutil.json_object([
    ("jsonrpc", @jsonutil.json_string("2.0")),
    ("id", @jsonutil.json_number(id)),
    ("method", @jsonutil.json_string("ping")),
  ])
}

///|
pub fn build_tools_list_request(id : Int, cursor? : String = "") -> String {
  if cursor == "" {
    @jsonutil.json_object([
      ("jsonrpc", @jsonutil.json_string("2.0")),
      ("id", @jsonutil.json_number(id)),
      ("method", @jsonutil.json_string("tools/list")),
    ])
  } else {
    let params = @jsonutil.json_object([
      ("cursor", @jsonutil.json_string(cursor)),
    ])
    @jsonutil.json_object([
      ("jsonrpc", @jsonutil.json_string("2.0")),
      ("id", @jsonutil.json_number(id)),
      ("method", @jsonutil.json_string("tools/list")),
      ("params", params),
    ])
  }
}

///|
pub fn build_tools_call_request(
  id : Int,
  name : String,
  arguments? : String = "{}",
  progress_token? : String = "",
) -> String {
  let params_pairs : Array[(String, String)] = [
    ("name", @jsonutil.json_string(name)),
    ("arguments", arguments),
  ]
  if progress_token != "" {
    params_pairs.push(
      (
        "_meta",
        @jsonutil.json_object([
          ("progressToken", @jsonutil.json_string(progress_token)),
        ]),
      ),
    )
  }
  let params = @jsonutil.json_object(params_pairs)
  @jsonutil.json_object([
    ("jsonrpc", @jsonutil.json_string("2.0")),
    ("id", @jsonutil.json_number(id)),
    ("method", @jsonutil.json_string("tools/call")),
    ("params", params),
  ])
}

///|
pub fn build_resources_list_request(id : Int, cursor? : String = "") -> String {
  if cursor == "" {
    @jsonutil.json_object([
      ("jsonrpc", @jsonutil.json_string("2.0")),
      ("id", @jsonutil.json_number(id)),
      ("method", @jsonutil.json_string("resources/list")),
    ])
  } else {
    let params = @jsonutil.json_object([
      ("cursor", @jsonutil.json_string(cursor)),
    ])
    @jsonutil.json_object([
      ("jsonrpc", @jsonutil.json_string("2.0")),
      ("id", @jsonutil.json_number(id)),
      ("method", @jsonutil.json_string("resources/list")),
      ("params", params),
    ])
  }
}

///|
pub fn build_resources_read_request(id : Int, uri : String) -> String {
  let params = @jsonutil.json_object([("uri", @jsonutil.json_string(uri))])
  @jsonutil.json_object([
    ("jsonrpc", @jsonutil.json_string("2.0")),
    ("id", @jsonutil.json_number(id)),
    ("method", @jsonutil.json_string("resources/read")),
    ("params", params),
  ])
}

///|
pub fn build_prompts_list_request(id : Int, cursor? : String = "") -> String {
  if cursor == "" {
    @jsonutil.json_object([
      ("jsonrpc", @jsonutil.json_string("2.0")),
      ("id", @jsonutil.json_number(id)),
      ("method", @jsonutil.json_string("prompts/list")),
    ])
  } else {
    let params = @jsonutil.json_object([
      ("cursor", @jsonutil.json_string(cursor)),
    ])
    @jsonutil.json_object([
      ("jsonrpc", @jsonutil.json_string("2.0")),
      ("id", @jsonutil.json_number(id)),
      ("method", @jsonutil.json_string("prompts/list")),
      ("params", params),
    ])
  }
}

///|
pub fn build_prompts_get_request(
  id : Int,
  name : String,
  arguments? : String = "{}",
) -> String {
  let params = @jsonutil.json_object([
    ("name", @jsonutil.json_string(name)),
    ("arguments", arguments),
  ])
  @jsonutil.json_object([
    ("jsonrpc", @jsonutil.json_string("2.0")),
    ("id", @jsonutil.json_number(id)),
    ("method", @jsonutil.json_string("prompts/get")),
    ("params", params),
  ])
}

///|
pub fn build_set_log_level_request(id : Int, level : String) -> String {
  let params = @jsonutil.json_object([("level", @jsonutil.json_string(level))])
  @jsonutil.json_object([
    ("jsonrpc", @jsonutil.json_string("2.0")),
    ("id", @jsonutil.json_number(id)),
    ("method", @jsonutil.json_string("logging/setLevel")),
    ("params", params),
  ])
}

///|
pub fn build_resources_subscribe_request(id : Int, uri : String) -> String {
  let params = @jsonutil.json_object([("uri", @jsonutil.json_string(uri))])
  @jsonutil.json_object([
    ("jsonrpc", @jsonutil.json_string("2.0")),
    ("id", @jsonutil.json_number(id)),
    ("method", @jsonutil.json_string("resources/subscribe")),
    ("params", params),
  ])
}

///|
pub fn build_resources_unsubscribe_request(id : Int, uri : String) -> String {
  let params = @jsonutil.json_object([("uri", @jsonutil.json_string(uri))])
  @jsonutil.json_object([
    ("jsonrpc", @jsonutil.json_string("2.0")),
    ("id", @jsonutil.json_number(id)),
    ("method", @jsonutil.json_string("resources/unsubscribe")),
    ("params", params),
  ])
}

///|
pub fn build_resources_templates_list_request(
  id : Int,
  cursor? : String = "",
) -> String {
  if cursor == "" {
    @jsonutil.json_object([
      ("jsonrpc", @jsonutil.json_string("2.0")),
      ("id", @jsonutil.json_number(id)),
      ("method", @jsonutil.json_string("resources/templates/list")),
    ])
  } else {
    let params = @jsonutil.json_object([
      ("cursor", @jsonutil.json_string(cursor)),
    ])
    @jsonutil.json_object([
      ("jsonrpc", @jsonutil.json_string("2.0")),
      ("id", @jsonutil.json_number(id)),
      ("method", @jsonutil.json_string("resources/templates/list")),
      ("params", params),
    ])
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
  let ref_obj = @jsonutil.json_object([
    ("type", @jsonutil.json_string(ref_type)),
    ("name", @jsonutil.json_string(ref_name)),
  ])
  let argument = @jsonutil.json_object([
    ("name", @jsonutil.json_string(argument_name)),
    ("value", @jsonutil.json_string(argument_value)),
  ])
  let params = @jsonutil.json_object([("ref", ref_obj), ("argument", argument)])
  @jsonutil.json_object([
    ("jsonrpc", @jsonutil.json_string("2.0")),
    ("id", @jsonutil.json_number(id)),
    ("method", @jsonutil.json_string("completion/complete")),
    ("params", params),
  ])
}
