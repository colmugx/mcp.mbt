///|
/// MCP protocol version implemented by this SDK.
///
/// Single source of truth for the `MCP-Protocol-Version` header and the
/// `_meta.io.modelcontextprotocol/protocolVersion` field. Per the 2026-07-28
/// revision, every request carries its own version; there is no handshake.
pub const ProtocolVersion : String = "2026-07-28"

///|
pub(all) struct ServerInfo {
  name : String
  title : String?
  version : String
  description : String?
} derive(Debug, Eq)

///|
pub(all) struct ServerCapabilities {
  tools : ToolCapabilities?
  resources : ResourceCapabilities?
  prompts : PromptCapabilities?
} derive(Debug, Eq)

///|
pub(all) struct ToolCapabilities {
  list_changed : Bool
} derive(Debug, Eq)

///|
pub(all) struct ResourceCapabilities {
  subscribe : Bool
  list_changed : Bool
} derive(Debug, Eq)

///|
pub(all) struct PromptCapabilities {
  list_changed : Bool
} derive(Debug, Eq)

///|
pub(all) struct ToolDefinition {
  name : String
  description : String
  input_schema : Json
  cached_schema_json : String
  icon : String?
} derive(Debug, Eq)

///|
/// Request ID supporting both Int and String per JSON-RPC 2.0 / MCP spec
pub(all) enum RequestId {
  Int(Int)
  Str(String)
} derive(Eq, Debug)

///|
/// Convert RequestId to its JSON string representation
pub fn RequestId::to_json_string(self : RequestId) -> String {
  match self {
    Int(n) => n.to_string()
    Str(s) => {
      // Produce a JSON-quoted string: "escaped_content"
      let escaped = s
        .replace(old="\\", new="\\\\")
        .replace(old="\"", new="\\\"")
        .replace(old="\n", new="\\n")
        .replace(old="\r", new="\\r")
        .replace(old="\t", new="\\t")
      "\"" + escaped + "\""
    }
  }
}

///|
pub(all) struct JsonRpcRequest {
  jsonrpc : String
  id : RequestId
  method_name : String
  params : Json
} derive(Debug, Eq)

///|
pub(all) struct JsonRpcResponse {
  jsonrpc : String
  id : RequestId
  result : Result[Json, JsonRpcError]
} derive(Debug, Eq)

///|
pub(all) struct JsonRpcError {
  code : Int
  message : String
  data : Json?
} derive(Debug, Eq)

///|
pub(all) struct PromptArgument {
  name : String
  description : String?
  required : Bool?
} derive(Debug, Eq)

///|
pub(all) struct Prompt {
  name : String
  description : String?
  arguments : Array[PromptArgument]?
} derive(Debug, Eq)

///|
/// Content item for MCP tool results
pub(all) enum ContentItem {
  Text(String)
  /// Image with base64 data and mime type
  Image(String, mime_type~ : String)
  /// Resource link (type: "resource_link") — references a resource by URI
  ResourceLink(String)
  /// Embedded resource (type: "resource") — contains inline text or blob content
  EmbeddedResource(EmbeddedResourceContent)
} derive(Eq, Debug)

///|
pub(all) enum EmbeddedResourceContent {
  Text(String, uri~ : String, mime_type~ : String?)
  Blob(String, uri~ : String, mime_type~ : String)
} derive(Eq, Debug)

///|
pub(all) struct PromptMessage {
  role : String
  content : ContentItem
} derive(Debug, Eq)

///|
pub(all) struct GetPromptResult {
  description : String?
  messages : Array[PromptMessage]
} derive(Debug, Eq)

///|
pub fn JsonRpcRequest::from_json(
  json : Json,
) -> Result[JsonRpcRequest, MCPError] {
  if json is Object(obj) {
    let jsonrpc = match obj.get("jsonrpc") {
      Some(String("2.0")) => "2.0"
      _ => return Err(InvalidRequest("Missing or invalid 'jsonrpc' field"))
    }
    let id = match obj.get("id") {
      Some(Number(n, ..)) => RequestId::Int(n.to_int())
      Some(String(s)) => RequestId::Str(s)
      _ => return Err(InvalidRequest("Missing or invalid 'id' field"))
    }
    let method_name = match obj.get("method") {
      Some(String(m)) => m
      _ => return Err(InvalidRequest("Missing or invalid 'method' field"))
    }
    let params = obj.get("params").unwrap_or(null)
    Ok({ jsonrpc, id, method_name, params })
  } else {
    Err(InvalidRequest("Request must be a JSON object"))
  }
}
