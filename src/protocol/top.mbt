///|
pub using @types {
  type MCPError,
  type TransportError,
  type JsonRpcRequest,
  type ServerInfo,
  type DiscoverResult,
  type ServerCapabilities,
  type ClientCapabilities,
  type RootCapabilities,
  type SamplingCapabilities,
  type SamplingMessage,
  type SamplingContent,
  type SamplingContentBlock,
  type SamplingContext,
  type CreateMessageRequest,
  type CreateMessageResult,
  type ModelPreferences,
  type ModelHint,
  type ToolChoice,
  type ToolChoiceMode,
  type ToolUseContent,
  type ToolResultContent,
  type ElicitationCapabilities,
  type ElicitationRequest,
  type ElicitationResult,
  type ElicitationAction,
  type ElicitationValue,
  type ToolCapabilities,
  type ResourceCapabilities,
  type PromptCapabilities,
  type ProgressToken,
  type ProgressNotification,
  type ToolDefinition,
  type ToolAnnotations,
  type ResultMetadata,
  type CacheScope,
  type CompletionReference,
  type CompletionArgument,
  type CompletionContext,
  type CompleteRequestParams,
  type CompletionResult,
  type PromptDefinition,
  type PromptArgument,
  type PromptMessage,
  type GetPromptResult,
  type ContentBlock,
  type ContentMetadata,
  type Annotations,
  type Role,
  type Icon,
  type IconTheme,
  type ResourceDefinition,
  type ResourceTemplateDefinition,
  type ResourceReadResult,
  type ResourceContents,
  type ResourceData,
  type ResourceLinkData,
}

///|
pub using @core {trait Params, type JsonSchema, type ToolError}

///|
pub using @core {tool_fn, simple_tool}

///|
pub using @tool {trait Tool, type ToolResult, type ParamDef}

///|
pub using @tool {
  get_number,
  get_optional_number,
  get_optional_string,
  get_string,
}
