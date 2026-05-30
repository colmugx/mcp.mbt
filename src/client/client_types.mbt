///|
pub(all) struct ListToolsResult {
  tools : Array[@types.ToolDefinition]
} derive(Show, Eq)

///|
pub(all) struct CallToolResult {
  content : Array[@types.ContentItem]
  is_error : Bool
} derive(Show, Eq)

///|
pub(all) struct ListResourcesResult {
  resources : Array[@resource.ResourceDefinition]
} derive(Show, Eq)

///|
pub(all) struct ReadResourceResult {
  contents : Array[@resource.ResourceReadResult]
} derive(Show, Eq)

///|
pub(all) struct ListPromptsResult {
  prompts : Array[@prompt.PromptDefinition]
} derive(Show, Eq)
