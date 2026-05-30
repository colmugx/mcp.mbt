///|
pub(all) struct NotificationHandlers {
  on_tools_changed : (() -> Unit)?
  on_resources_changed : (() -> Unit)?
  on_prompts_changed : (() -> Unit)?
}

///|
pub fn NotificationHandlers::empty() -> NotificationHandlers {
  {
    on_tools_changed: None,
    on_resources_changed: None,
    on_prompts_changed: None,
  }
}

///|
pub fn handle_server_notification(
  handlers : NotificationHandlers,
  notification : @types.Notification,
) -> Unit {
  match notification.method_name {
    "notifications/tools/list_changed" =>
      match handlers.on_tools_changed {
        Some(h) => h()
        None => ()
      }
    "notifications/resources/list_changed" =>
      match handlers.on_resources_changed {
        Some(h) => h()
        None => ()
      }
    "notifications/prompts/list_changed" =>
      match handlers.on_prompts_changed {
        Some(h) => h()
        None => ()
      }
    _ => ()
  }
}
