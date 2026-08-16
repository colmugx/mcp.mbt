///|
pub(all) struct ListToolsResult {
  tools : Array[@types.ToolDefinition]
  next_cursor : String?
} derive(Debug, Eq)

///|
pub(all) struct CallToolResult {
  content : Array[@types.ContentItem]
  is_error : Bool
} derive(Debug, Eq)

///|
pub(all) struct ListResourcesResult {
  resources : Array[@resource.ResourceDefinition]
  next_cursor : String?
} derive(Debug, Eq)

///|
pub(all) struct ReadResourceResult {
  contents : Array[@resource.ResourceReadResult]
} derive(Debug, Eq)

///|
pub(all) struct ListPromptsResult {
  prompts : Array[@prompt.PromptDefinition]
  next_cursor : String?
} derive(Debug, Eq)

///|
pub(all) struct ResourceTemplate {
  uri_template : String
  name : String
  description : String?
  mime_type : String?
} derive(Debug, Eq)

///|
pub(all) struct ListResourceTemplatesResult {
  resource_templates : Array[ResourceTemplate]
  next_cursor : String?
} derive(Debug, Eq)

///|
pub(all) struct CompletionResult {
  values : Array[String]
  total : Int?
  has_more : Bool?
} derive(Debug, Eq)

///|
/// Filter for a `subscriptions/listen` request. Controls which server
/// notification channels the client wants multiplexed onto this single
/// long-lived request.
pub(all) struct ListenFilter {
  tools_list_changed : Bool
  prompts_list_changed : Bool
  resources_list_changed : Bool
  resource_subscriptions : Array[String]
} derive(Debug, Eq)

///|
/// Default filter: subscribe only to list-change notifications, with no
/// per-resource subscriptions.
pub fn ListenFilter::default() -> ListenFilter {
  {
    tools_list_changed: true,
    prompts_list_changed: true,
    resources_list_changed: true,
    resource_subscriptions: [],
  }
}
