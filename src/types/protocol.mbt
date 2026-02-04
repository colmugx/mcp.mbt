///|
pub(all) struct ServerInfo {
  name : String
  version : String
} derive(Show, Eq)

///|
pub(all) struct ServerCapabilities {
  tools : ToolCapabilities?
  resources : ResourceCapabilities?
  prompts : PromptCapabilities?
} derive(Show, Eq)

///|
pub(all) struct ToolCapabilities {
  list_changed : Bool
} derive(Show, Eq)

///|
pub(all) struct ResourceCapabilities {
  subscribe : Bool
  list_changed : Bool
} derive(Show, Eq)

///|
pub(all) struct PromptCapabilities {
  list_changed : Bool
} derive(Show, Eq)

///|
pub(all) struct ToolDefinition {
  name : String
  description : String
  input_schema : Json
  cached_schema_json : String
} derive(Show, Eq)

///|
pub(all) struct JsonRpcRequest {
  jsonrpc : String
  id : Int
  method_name : String
  params : Json
} derive(Show, Eq)

///|
pub(all) struct JsonRpcResponse {
  jsonrpc : String
  id : Int
  result : Result[Json, JsonRpcError]
} derive(Show, Eq)

///|
pub(all) struct JsonRpcError {
  code : Int
  message : String
  data : Json?
} derive(Show, Eq)

///|
pub(all) struct PromptArgument {
  name : String
  description : String?
  required : Bool?
} derive(Show, Eq)

///|
pub(all) struct Prompt {
  name : String
  description : String?
  arguments : Array[PromptArgument]?
} derive(Show, Eq)

///|
pub(all) struct PromptMessage {
  role : String
  content : @tool.ContentItem
} derive(Show, Eq)

///|
pub(all) struct GetPromptResult {
  description : String?
  messages : Array[PromptMessage]
} derive(Show, Eq)

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
      Some(Number(n, ..)) => n.to_int()
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
