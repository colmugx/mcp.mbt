///|
/// Protocol types
pub using @ptypes {
  type MCPError,
  type TransportError,
  type JsonRpcRequest,
  type ServerInfo,
  type ServerCapabilities,
  type ToolDefinition,
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
pub using @server {type MCPServer}

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
