///|
pub fn build_initialize_request(
  id : Int,
  client_name : String,
  client_version : String,
) -> String {
  let client_info = @jsonutil.json_object([
    ("name", @jsonutil.json_string(client_name)),
    ("version", @jsonutil.json_string(client_version)),
  ])
  let params = @jsonutil.json_object([
    ("protocolVersion", @jsonutil.json_string("2025-11-25")),
    ("capabilities", "{}"),
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
pub fn build_tools_list_request(id : Int) -> String {
  @jsonutil.json_object([
    ("jsonrpc", @jsonutil.json_string("2.0")),
    ("id", @jsonutil.json_number(id)),
    ("method", @jsonutil.json_string("tools/list")),
  ])
}

///|
pub fn build_tools_call_request(
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
    ("method", @jsonutil.json_string("tools/call")),
    ("params", params),
  ])
}

///|
pub fn build_resources_list_request(id : Int) -> String {
  @jsonutil.json_object([
    ("jsonrpc", @jsonutil.json_string("2.0")),
    ("id", @jsonutil.json_number(id)),
    ("method", @jsonutil.json_string("resources/list")),
  ])
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
pub fn build_prompts_list_request(id : Int) -> String {
  @jsonutil.json_object([
    ("jsonrpc", @jsonutil.json_string("2.0")),
    ("id", @jsonutil.json_number(id)),
    ("method", @jsonutil.json_string("prompts/list")),
  ])
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
