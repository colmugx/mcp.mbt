///| MCP Error Types
/// Defines error types for the MCP protocol and transport layers

///|
/// Transport-level errors
/// These occur at the communication layer (network, IO, etc.)
pub(all) suberror TransportError {
  /// Connection has been closed (clean shutdown)
  ConnectionClosed
  /// Failed to read from transport
  ReadError(String)
  /// Failed to write to transport
  WriteError(String)
  /// Operation timed out
  Timeout
  /// Invalid transport state (e.g., trying to send after close)
  InvalidState(String)
} derive(Show, Eq)

///|
/// MCP protocol-level errors
/// These follow the JSON-RPC 2.0 error code conventions
pub(all) suberror MCPError {
  /// Failed to parse JSON-RPC request (-32700)
  ParseError(String)
  /// Invalid JSON-RPC request structure (-32600)
  InvalidRequest(String)
  /// Method not found (-32601)
  MethodNotFound(String)
  /// Invalid method parameters (-32602)
  InvalidParams(String)
  /// Internal MCP server error (-32603)
  InternalError(String)
  /// Transport layer error (wrapped)
  TransportError(TransportError)
  /// Tool execution error (custom error code -32000)
  ToolError(String)
} derive(Show, Eq)

///|
/// Convert MCPError to JSON-RPC error code
pub fn MCPError::to_error_code(self : MCPError) -> Int {
  match self {
    ParseError(_) => -32700
    InvalidRequest(_) => -32600
    MethodNotFound(_) => -32601
    InvalidParams(_) => -32602
    InternalError(_) => -32603
    TransportError(_) => -32603 // Map transport errors to internal error
    ToolError(_) => -32000 // Server-defined error
  }
}

///|
/// Get error message from MCPError
pub fn MCPError::message(self : MCPError) -> String {
  match self {
    ParseError(msg) => msg
    InvalidRequest(msg) => msg
    MethodNotFound(msg) => msg
    InvalidParams(msg) => msg
    InternalError(msg) => msg
    TransportError(te) => "Transport error: " + te.to_string()
    ToolError(msg) => msg
  }
}
