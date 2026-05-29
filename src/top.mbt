///|
/// Protocol types
pub using @ptypes {
  type MCPError,
  type TransportError,
  type JsonRpcRequest,
  type JsonRpcResponse,
  type ServerInfo,
  type ServerCapabilities,
  type ToolDefinition,
  type ContentItem,
}

///|
/// Protocol tool types
pub using @ptool {
  trait Tool,
  type ToolResult,
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
pub using @server {mcp_server, type MCPServer}

///|
/// Transport
pub using @transport {
  type AnyTransport,
  type StdioTransport,
  type HttpTransport,
}
