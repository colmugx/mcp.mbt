///|
pub(all) struct ListToolsResult {
  tools : Array[@types.ToolDefinition]
  next_cursor : String?
} derive(Show, Eq)

///|
pub(all) struct CallToolResult {
  content : Array[@types.ContentItem]
  is_error : Bool
} derive(Show, Eq)

///|
pub(all) struct ListResourcesResult {
  resources : Array[@resource.ResourceDefinition]
  next_cursor : String?
} derive(Show, Eq)

///|
pub(all) struct ReadResourceResult {
  contents : Array[@resource.ResourceReadResult]
} derive(Show, Eq)

///|
pub(all) struct ListPromptsResult {
  prompts : Array[@prompt.PromptDefinition]
  next_cursor : String?
} derive(Show, Eq)

///|
pub(all) struct ResourceTemplate {
  uri_template : String
  name : String
  description : String?
  mime_type : String?
} derive(Show, Eq)

///|
pub(all) struct ListResourceTemplatesResult {
  resource_templates : Array[ResourceTemplate]
  next_cursor : String?
} derive(Show, Eq)

///|
pub(all) struct CompletionResult {
  values : Array[String]
  total : Int?
  has_more : Bool?
} derive(Show, Eq)
