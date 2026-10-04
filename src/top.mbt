///|
/// Parse schema/instance JSON without discarding numeric literal precision.
pub using @validation {parse_json}

///|
/// Protocol types
pub using @ptypes {
  type MCPError,
  type TransportError,
  type JsonRpcRequest,
  type RequestId,
  type InputRequestEntry,
  type InputRequestKind,
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
/// Protocol tool types
pub using @ptool {
  trait Tool,
  type ToolResult,
  type ToolCallOutcome,
  type ParamDef,
  get_number,
  get_optional_number,
  get_optional_string,
  get_string,
}

///|
/// Protocol core
pub using @pcore {
  trait Params,
  type JsonSchema,
  type ToolError,
  tool_fn,
  simple_tool,
}

///|
/// Server
pub using @server {type MCPServer, type CompletionRegistry}

///|
pub using @runtime {
  type RequestContext,
  type Principal,
  type CancellationToken,
  type ProgressReporter,
  type RequestCancelled,
}

///|
/// Client and Host
pub using @client {
  type MCPClient,
  type MCPHost,
  type ListToolsResult,
  type CallToolResult,
  type ListResourcesResult,
  type ReadResourceResult,
  type ListPromptsResult,
  type CompletionResult,
}
