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
  /// Optional protocol extensions, per 2026-07-28 versioning: a map of
  /// extension identifiers (following `_meta` key naming rules) to
  /// per-extension settings objects.
  extensions : Map[String, Json]?
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
    // Delegate string quoting to the Json serializer so every JSON escape
    // (\b, \f, other control chars < 0x20) is emitted correctly; a
    // hand-rolled escape list could produce invalid JSON text.
    Str(s) => Json::string(s).stringify()
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
pub(all) struct PromptArgument {
  name : String
  description : String?
  required : Bool?
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
    Ok({ jsonrpc, id, method_name, params, })
  } else {
    Err(InvalidRequest("Request must be a JSON object"))
  }
}

///|
/// MRTR (Multi Round-Trip Requests) — 2026-07-28 spec basic/patterns/mrtr.
///
/// When a server needs client input (sampling/elicitation/roots) to finish a
/// request, it returns an `InputRequiredResult` whose `inputRequests` lists
/// what it needs and `requestState` carries server-side continuation state.
/// The client fulfills the inputs and retries the original request with
/// `inputResponses` + the echoed `requestState`.

///|
/// The three server→client input request methods. Servers MUST NOT send an
/// input request the client did not declare support for in its capabilities.
pub(all) enum InputRequestKind {
  ElicitationCreate
  SamplingCreateMessage
  RootsList
} derive(Eq, Debug)

///|
/// One entry in an `inputRequests` map: a server-assigned key plus the
/// request method and params the client must fulfill.
pub(all) struct InputRequestEntry {
  method_name : InputRequestKind
  params : Json
} derive(Eq, Debug)

///|
/// Convert an `InputRequestKind` to its JSON-RPC method string.
pub fn InputRequestKind::to_method(self : InputRequestKind) -> String {
  match self {
    ElicitationCreate => "elicitation/create"
    SamplingCreateMessage => "sampling/createMessage"
    RootsList => "roots/list"
  }
}

///|
/// Which kind of change notification a subscription filter should match.
/// Used internally by the server to route notifications to the right streams.
pub(all) enum SubscriptionNotificationKind {
  ToolsListChanged
  PromptsListChanged
  ResourcesListChanged
  /// A specific subscribed resource changed; matched against the
  /// subscription's `resourceSubscriptions` URI list.
  ResourceUpdated(uri~ : String)
} derive(Eq, Debug)
