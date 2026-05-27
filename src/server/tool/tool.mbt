///|
/// Content item for MCP tool results
pub(all) enum ContentItem {
  Text(String)
  /// Image with base64 data and mime type
  Image(String, mime_type~ : String)
  /// Resource reference with URI
  Resource(String)
} derive(Eq, Show)

///|
/// Tool execution result following MCP protocol format
pub struct ToolResult {
  content : Array[ContentItem]
  is_error : Bool
} derive(Eq, Show)

///|
/// Create a successful result with text content
pub fn ToolResult::text(text : String) -> ToolResult {
  { content: [Text(text)], is_error: false }
}

///|
/// Create a successful result with multiple content items
pub fn ToolResult::success(content : Array[ContentItem]) -> ToolResult {
  { content, is_error: false }
}

///|
/// Create an error result with error message
pub fn ToolResult::error(message : String) -> ToolResult {
  { content: [Text(message)], is_error: true }
}

///| ToToolResult Trait (Maria-inspired type conversion)

///|
/// Trait for types that can be converted to ToolResult
pub trait ToToolResult {
  to_tool_result(Self) -> ToolResult
}

///|
/// Built-in conversion from String
pub impl ToToolResult for String with to_tool_result(self : String) -> ToolResult {
  ToolResult::text(self)
}

///|
/// Built-in conversion from Int
pub impl ToToolResult for Int with to_tool_result(self : Int) -> ToolResult {
  ToolResult::text(self.to_string())
}

///|
/// Built-in conversion from Bool
pub impl ToToolResult for Bool with to_tool_result(self : Bool) -> ToolResult {
  ToolResult::text(self.to_string())
}

///|
/// Built-in conversion from Double (number)
pub impl ToToolResult for Double with to_tool_result(self : Double) -> ToolResult {
  ToolResult::text(self.to_string())
}

///|
/// Built-in conversion from ToolResult (identity)
pub impl ToToolResult for ToolResult with to_tool_result(self : ToolResult) -> ToolResult {
  self
}

///|
/// Parameter definition for tool schema
pub(all) struct ParamDef {
  name : String
  description : String
  type_ : String // "string", "number", "boolean", "object", "array"
  required : Bool
} derive(Eq, Show)

///|
/// Core Tool trait following MCP protocol
pub(open) trait Tool {
  name(Self) -> String
  description(Self) -> String
  params(Self) -> Array[ParamDef]
  async execute(Self, Json) -> ToolResult
}

///|
/// Extract string from JSON, returning error ToolResult on failure
pub fn get_string(json : Json, key : String) -> Result[String, ToolResult] {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => Ok(s)
        Some(_) => Err(ToolResult::error("Field '\{key}' is not a string"))
        None => Err(ToolResult::error("Missing required field '\{key}'"))
      }
    _ => Err(ToolResult::error("Expected JSON object"))
  }
}

///|
/// Extract number from JSON, returning error ToolResult on failure
pub fn get_number(json : Json, key : String) -> Result[Double, ToolResult] {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(Number(n, ..)) => Ok(n)
        Some(_) => Err(ToolResult::error("Field '\{key}' is not a number"))
        None => Err(ToolResult::error("Missing required field '\{key}'"))
      }
    _ => Err(ToolResult::error("Expected JSON object"))
  }
}

///|
/// Extract optional string from JSON
pub fn get_optional_string(
  json : Json,
  key : String,
) -> Result[String?, ToolResult] {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => Ok(Some(s))
        Some(Null) => Ok(None)
        None => Ok(None)
        Some(_) => Err(ToolResult::error("Field '\{key}' is not a string"))
      }
    _ => Err(ToolResult::error("Expected JSON object"))
  }
}

///|
/// Extract optional number from JSON
pub fn get_optional_number(
  json : Json,
  key : String,
) -> Result[Double?, ToolResult] {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(Number(n, ..)) => Ok(Some(n))
        Some(Null) => Ok(None)
        None => Ok(None)
        Some(_) => Err(ToolResult::error("Field '\{key}' is not a number"))
      }
    _ => Err(ToolResult::error("Expected JSON object"))
  }
}
