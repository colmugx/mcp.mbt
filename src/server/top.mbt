///|
pub using @tool {
  get_number,
  get_optional_number,
  get_optional_string,
  get_string,
}

///|
pub using @tool {
  trait Tool,
  type ToolResult,
  type ToolCallOutcome,
  type ParamDef,
}

///|
pub using @core {trait Params, type JsonSchema, type ToolError}

///|
pub using @core {tool_fn, simple_tool}

///|
pub using @runtime {
  type RequestContext,
  type Principal,
  type CancellationToken,
  type ProgressReporter,
  type RequestCancelled,
}

///|
pub using @types {
  type MCPError,
  type TransportError,
  type RequestId,
  type JsonRpcRequest,
  type ServerInfo,
  type ServerCapabilities,
  type ToolDefinition,
  type ToolAnnotations,
  type ResultMetadata,
  type CacheScope,
  type CompletionReference,
  type CompletionArgument,
  type CompletionContext,
  type CompleteRequestParams,
  type CompletionResult,
  type InputRequestEntry,
  type InputRequestKind,
  type ContentBlock,
  type ContentMetadata,
  type Annotations,
  type Role,
  type Icon,
  type IconTheme,
  type ResourceContents,
  type ResourceData,
  type ResourceLinkData,
}
