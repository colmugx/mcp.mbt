///|
pub fn handle_server_notification(
  client : MCPClient,
  notification : @types.Notification,
) -> Unit {
  match notification.method_name {
    "notifications/tools/list_changed" =>
      match client.on_tools_changed {
        Some(handler) => handler()
        None => ()
      }
    "notifications/resources/list_changed" =>
      match client.on_resources_changed {
        Some(handler) => handler()
        None => ()
      }
    "notifications/prompts/list_changed" =>
      match client.on_prompts_changed {
        Some(handler) => handler()
        None => ()
      }
    _ => ()
  }
}
