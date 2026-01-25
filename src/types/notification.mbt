///| Notification Types - MCP Protocol Implementation

///| Based on: MCP Protocol 2025-06-18 specification

///|=====================================================

///| Notification Type

///|=====================================================

///|
/// Server notification sent to clients
/// Follows MCP spec notification format
pub(all) struct Notification {
  method : String
  params : Json?
} derive(Eq, Show)

///|=====================================================

///| Notification Capabilities

///|=====================================================

///|
/// Server notification capabilities
pub(all) struct NotificationCapabilities {
  tools_list_changed : Bool
  resources_list_changed : Bool
  resources_updated : Bool
  prompts_list_changed : Bool
} derive(Eq, Show)

///|=====================================================

///| Notification Factory Methods

///|=====================================================

///|
/// Create tools list changed notification
pub fn tools_list_changed_notification() -> Notification {
  { method: "notifications/tools/list_changed", params: None }
}

///|
/// Create resources list changed notification
pub fn resources_list_changed_notification() -> Notification {
  { method: "notifications/resources/list_changed", params: None }
}

///|
/// Create prompts list changed notification
pub fn prompts_list_changed_notification() -> Notification {
  { method: "notifications/prompts/list_changed", params: None }
}
