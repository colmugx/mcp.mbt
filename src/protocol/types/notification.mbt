///| Notification Types - MCP Protocol Implementation

///| Based on: MCP Protocol 2026-07-28 specification

///|
/// Server notification sent to clients
/// Follows MCP spec notification format
pub(all) struct Notification {
  method_name : String
  params : Json?
} derive(Eq, Debug)

///|
/// Server notification capabilities
pub(all) struct NotificationCapabilities {
  tools_list_changed : Bool
  resources_list_changed : Bool
  resources_updated : Bool
  prompts_list_changed : Bool
} derive(Eq, Debug)

///|
/// Create tools list changed notification
pub fn tools_list_changed_notification() -> Notification {
  { method_name: "notifications/tools/list_changed", params: None }
}

///|
/// Create resources list changed notification
pub fn resources_list_changed_notification() -> Notification {
  { method_name: "notifications/resources/list_changed", params: None }
}

///|
/// Create prompts list changed notification
pub fn prompts_list_changed_notification() -> Notification {
  { method_name: "notifications/prompts/list_changed", params: None }
}

///|
/// Create resources updated notification with URI parameter
pub fn resources_updated_notification(uri : String) -> Notification {
  {
    method_name: "notifications/resources/updated",
    params: Some(Json::object({ "uri": uri })),
  }
}

///|
/// Create progress notification
pub fn progress_notification(
  token : String,
  progress : Double,
  total? : Double,
) -> Notification {
  let params_map : Map[String, Json] = Default::default()
  params_map.set("progressToken", Json::string(token))
  params_map.set("progress", Json::number(progress))
  match total {
    Some(t) => params_map.set("total", Json::number(t))
    None => ()
  }
  {
    method_name: "notifications/progress",
    params: Some(Json::object(params_map)),
  }
}

///|
/// Create cancelled notification
pub fn cancelled_notification(
  request_id : String,
  reason? : String,
) -> Notification {
  let params_map : Map[String, Json] = Default::default()
  params_map.set("requestId", Json::string(request_id))
  match reason {
    Some(r) => params_map.set("reason", Json::string(r))
    None => ()
  }
  {
    method_name: "notifications/cancelled",
    params: Some(Json::object(params_map)),
  }
}

///|
/// Serialize notification to JSON-RPC string
pub fn Notification::to_jsonrpc_string(self : Notification) -> String {
  match self.params {
    Some(p) =>
      Json::object({ "jsonrpc": "2.0", "method": self.method_name, "params": p }).stringify()
    None =>
      Json::object({ "jsonrpc": "2.0", "method": self.method_name }).stringify()
  }
}
