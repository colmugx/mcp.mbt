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
  /// HTTP 401 Unauthorized — includes WWW-Authenticate header info
  Unauthorized(String)
  /// HTTP 403 Forbidden — insufficient scope or permissions
  Forbidden(String)
  /// HTTP error status carrying the response body, so callers (e.g. the
  /// era probe) can inspect it for a recognized modern JSON-RPC error
  /// (UnsupportedProtocolVersion / MissingRequiredClientCapability /
  /// HeaderMismatch) before deciding on a legacy fallback.
  HttpError(Int, String)
} derive(Debug, Eq)

///|
pub impl Show for TransportError with fn to_string(self) -> String {
  match self {
    ConnectionClosed => "Connection closed"
    ReadError(msg) => "Read error: " + msg
    WriteError(msg) => "Write error: " + msg
    Timeout => "Timeout"
    InvalidState(msg) => "Invalid state: " + msg
    Unauthorized(msg) => "Unauthorized: " + msg
    Forbidden(msg) => "Forbidden: " + msg
    HttpError(status, body) =>
      "HTTP " + status.to_string() + " error, body: " + body
  }
}

///|
/// MCP protocol-level errors
/// These follow the JSON-RPC 2.0 error code conventions.
///
/// Error code allocation (per 2026-07-28 spec):
/// - `-32700`, `-32600`..`-32603`: standard JSON-RPC 2.0
/// - `-32000`..`-32019`: legacy/implementation-defined (no new allocations)
/// - `-32020`..`-32099`: reserved for the MCP specification
pub(all) suberror MCPError {
  /// Failed to parse JSON-RPC request (-32700)
  ParseError(String)
  /// Invalid JSON-RPC request structure (-32600)
  InvalidRequest(String)
  /// Method not found (-32601)
  MethodNotFound(String)
  /// Invalid method parameters (-32602).
  /// Also used for resource-not-found (was -32002 in earlier revisions).
  InvalidParams(String)
  /// Internal MCP server error (-32603)
  InternalError(String)
  /// Transport layer error (wrapped)
  TransportError(TransportError)
  /// Tool execution error (implementation-defined, -32000)
  ToolError(String)
  /// Streamable HTTP header/body mismatch (-32020, MCP-spec-defined).
  /// `data` carries detail; server returns HTTP 400.
  HeaderMismatch(String)
  /// Request needs a client capability the client did not declare
  /// (-32021, MCP-spec-defined). `required` lists the missing capabilities.
  MissingRequiredClientCapability(String, required~ : Array[String])
  /// Client requested an unsupported protocol version
  /// (-32022, MCP-spec-defined). `supported` lists the versions the server
  /// can speak; `requested` echoes what the client asked for.
  UnsupportedProtocolVersion(
    String,
    supported~ : Array[String],
    requested~ : String
  )
} derive(Debug, Eq)

///|
/// Convert MCPError to JSON-RPC error code
pub fn MCPError::to_error_code(self : MCPError) -> Int {
  match self {
    ParseError(_) => -32700
    InvalidRequest(_) => -32600
    MethodNotFound(_) => -32601
    InvalidParams(_) => -32602
    InternalError(_) => -32603
    TransportError(_) => -32603
    ToolError(_) => -32000
    HeaderMismatch(_) => -32020
    MissingRequiredClientCapability(_, ..) => -32021
    UnsupportedProtocolVersion(_, ..) => -32022
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
    HeaderMismatch(msg) => msg
    MissingRequiredClientCapability(msg, ..) => msg
    UnsupportedProtocolVersion(msg, ..) => msg
  }
}

///|
/// Serialize the structured `data` member of a JSON-RPC error response.
/// Returns `None` for errors that carry no `data` per the spec. The
/// `-3202x` MCP-spec-defined errors populate `data` with fields clients
/// use for recovery (e.g. supported versions to retry with).
pub fn MCPError::to_error_data(self : MCPError) -> Json? {
  match self {
    UnsupportedProtocolVersion(_, supported~, requested~) => {
      let versions = supported.map(fn(v) { Json::string(v) })
      Some(
        Json::object({
          "supported": Json::array(versions),
          "requested": requested,
        }),
      )
    }
    MissingRequiredClientCapability(_, required~) => {
      let caps = required.map(fn(c) { Json::string(c) })
      Some(Json::object({ "requiredCapabilities": Json::array(caps) }))
    }
    _ => None
  }
}
