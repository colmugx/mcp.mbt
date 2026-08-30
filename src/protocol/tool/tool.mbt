///|
/// Tool execution result following MCP protocol format
pub struct ToolResult {
  content : Array[@types.ContentItem]
  is_error : Bool
} derive(Eq, Debug)

///|
/// Outcome of a tool execution. Per the 2026-07-28 MRTR pattern, a tool may
/// either complete normally (`Complete`) or request additional client input
/// (`InputRequired`). On retry, the client resubmits with `inputResponses`
/// and the echoed `requestState`; the tool then receives those responses via
/// its arguments and returns `Complete`.
pub(all) enum ToolCallOutcome {
  /// Normal completion — the tool finished and produced a result.
  Complete(ToolResult)
  /// The tool needs client input before it can finish. `input_requests`
  /// maps server-assigned keys to elicitation/sampling/roots requests;
  /// `state` is the server's continuation data (sealed into `requestState`
  /// by the handler before being sent to the client).
  InputRequired(
    input_requests~ : Map[String, @types.InputRequestEntry],
    state~ : Json
  )
} derive(Eq, Debug)

///|
/// Create a successful result with text content
pub fn ToolResult::text(text : String) -> ToolResult {
  { content: [@types.ContentItem::Text(text)], is_error: false, }
}

///|
/// Create a successful result with multiple content items
pub fn ToolResult::success(content : Array[@types.ContentItem]) -> ToolResult {
  { content, is_error: false, }
}

///|
/// Create an error result with error message
pub fn ToolResult::error(message : String) -> ToolResult {
  { content: [@types.ContentItem::Text(message)], is_error: true, }
}

///|
/// Parameter definition for tool schema
pub(all) struct ParamDef {
  name : String
  description : String
  type_ : String // "string", "number", "boolean", "object", "array"
  required : Bool
} derive(Eq, Debug)

///|
/// Core Tool trait following MCP protocol
pub(open) trait Tool {
  fn name(Self) -> String
  fn description(Self) -> String
  fn params(Self) -> Array[ParamDef]
  /// Execute the tool. Returns `Complete` for a normal result, or
  /// `InputRequired` to trigger an MRTR round-trip (the client will be asked
  /// for input and the request retried with `inputResponses`).
  async fn execute(Self, Json) -> ToolCallOutcome
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
