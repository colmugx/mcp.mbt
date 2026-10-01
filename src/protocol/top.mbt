///|
pub using @types {
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
