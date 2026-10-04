///|
pub(all) struct ListToolsResult {
  tools : Array[@types.ToolDefinition]
  next_cursor : String?
  metadata : @types.ResultMetadata
} derive(Debug, Eq)

///|
pub type CallToolResult = @types.ToolResult

///|
pub(all) struct ListResourcesResult {
  resources : Array[@resource.ResourceDefinition]
  next_cursor : String?
  metadata : @types.ResultMetadata
} derive(Debug, Eq)

///|
pub(all) struct ReadResourceResult {
  contents : Array[@types.ResourceContents]
  metadata : @types.ResultMetadata
} derive(Debug, Eq)

///|
pub(all) struct ListPromptsResult {
  prompts : Array[@prompt.PromptDefinition]
  next_cursor : String?
  metadata : @types.ResultMetadata
} derive(Debug, Eq)

///|
pub(all) struct ResourceTemplate {
  uri_template : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  icons : Array[@types.Icon]?
  metadata : @types.ContentMetadata
} derive(Debug, Eq)

///|
pub(all) struct ListResourceTemplatesResult {
  resource_templates : Array[ResourceTemplate]
  next_cursor : String?
  metadata : @types.ResultMetadata
} derive(Debug, Eq)

///|
pub using @types {
  type DiscoverResult,
  type CompletionResult,
  type CompletionReference,
  type CompletionArgument,
  type CompletionContext,
  type CompleteRequestParams,
}

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

///|
pub extend ListToolsResult with Debug::{to_repr}

///|
pub extend ListToolsResult with Eq::{not_equal, equal}

///|
pub extend ListResourcesResult with Debug::{to_repr}

///|
pub extend ListResourcesResult with Eq::{not_equal, equal}

///|
pub extend ReadResourceResult with Debug::{to_repr}

///|
pub extend ReadResourceResult with Eq::{not_equal, equal}

///|
pub extend ListPromptsResult with Debug::{to_repr}

///|
pub extend ListPromptsResult with Eq::{not_equal, equal}

///|
pub extend ResourceTemplate with Debug::{to_repr}

///|
pub extend ResourceTemplate with Eq::{not_equal, equal}

///|
pub extend ListResourceTemplatesResult with Debug::{to_repr}

///|
pub extend ListResourceTemplatesResult with Eq::{not_equal, equal}

///|
pub extend ListenFilter with Debug::{to_repr}

///|
pub extend ListenFilter with Eq::{not_equal, equal}
