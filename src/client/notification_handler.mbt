///|
pub(all) struct NotificationHandlers {
  on_tools_changed : (() -> Unit)?
  on_resources_changed : (() -> Unit)?
  on_prompts_changed : (() -> Unit)?
  on_progress : ((@types.ProgressNotification) -> Unit)?
  on_cancelled : ((@types.CancelledNotification) -> Unit)?
  on_resource_updated : ((@types.ResourceUpdatedNotification) -> Unit)?
  on_message : ((String, Json?) -> Unit)?
}

///|
pub fn NotificationHandlers::empty() -> NotificationHandlers {
  {
    on_tools_changed: None,
    on_resources_changed: None,
    on_prompts_changed: None,
    on_progress: None,
    on_cancelled: None,
    on_resource_updated: None,
    on_message: None,
  }
}

///|
fn handle_server_notification(
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
    "notifications/progress" =>
      match (handlers.on_progress, notification.params) {
        (Some(h), Some(Object(obj))) => {
          let parsed = parse_progress_notification(obj)
          match parsed {
            Some(pn) => h(pn)
            None => ()
          }
        }
        _ => ()
      }
    "notifications/cancelled" =>
      match (handlers.on_cancelled, notification.params) {
        (Some(h), Some(Object(obj))) => {
          let parsed = parse_cancelled_notification(obj)
          match parsed {
            Some(cn) => h(cn)
            None => ()
          }
        }
        _ => ()
      }
    "notifications/resources/updated" =>
      match (handlers.on_resource_updated, notification.params) {
        (Some(h), Some(Object(obj))) =>
          match obj.get("uri") {
            Some(String(uri)) => h({ uri, })
            _ => ()
          }
        _ => ()
      }
    _ =>
      match handlers.on_message {
        Some(h) => h(notification.method_name, notification.params)
        None => ()
      }
  }
}

///|
fn parse_progress_notification(
  obj : Map[String, Json],
) -> @types.ProgressNotification? {
  match obj.get("progressToken") {
    Some(String(token)) => {
      let progress = match obj.get("progress") {
        Some(Number(n, ..)) => n
        _ => return None
      }
      let total = match obj.get("total") {
        Some(Number(n, ..)) => Some(n)
        _ => None
      }
      let message = match obj.get("message") {
        Some(String(m)) => Some(m)
        _ => None
      }
      Some({ progress_token: token, progress, total, message })
    }
    _ => None
  }
}

///|
fn parse_cancelled_notification(
  obj : Map[String, Json],
) -> @types.CancelledNotification? {
  let request_id = match obj.get("requestId") {
    Some(Number(n, ..)) => @types.RequestId::Int(n.to_int())
    Some(String(s)) => @types.RequestId::Str(s)
    _ => return None
  }
  let reason = match obj.get("reason") {
    Some(String(r)) => Some(r)
    _ => None
  }
  Some({ request_id, reason })
}
