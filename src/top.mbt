///|
pub using @tool {
  get_number,
  get_optional_number,
  get_optional_string,
  get_string,
}

///|
pub using @tool {trait Tool, type ToolResult, type ContentItem, type ParamDef}

///|
pub using @server {
  boolean_param,
  expand_params_to_json,
  number_param,
  optional_boolean_param,
  optional_number_param,
  optional_string_param,
  string_param,
}

///|
pub using @server {type MCPServer, type ToolRegistry}

///|
pub using @transport {
  type AnyTransport,
  type StdioTransport,
  type HttpTransport,
}

///|
pub using @types {
  type MCPError,
  type TransportError,
  type JsonRpcRequest,
  type JsonRpcResponse,
  type ServerInfo,
  type ServerCapabilities,
  type ToolDefinition,
}
