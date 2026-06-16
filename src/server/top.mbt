///|
pub using @tool {
  get_number,
  get_optional_number,
  get_optional_string,
  get_string,
}

///|
pub using @tool {trait Tool, type ToolResult, type ParamDef}

///|
pub using @core {trait Params, type JsonSchema, type ToolError}

///|
pub using @core {tool_fn, simple_tool}

///|
pub using @types {
  type MCPError,
  type TransportError,
  type RequestId,
  type JsonRpcRequest,
  type JsonRpcResponse,
  type ServerInfo,
  type ServerCapabilities,
  type ToolDefinition,
  type ContentItem,
}
