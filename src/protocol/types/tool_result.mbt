///|
pub(all) struct ToolResult {
  content : Array[ContentBlock]
  structured_content : Json?
  is_error : Bool?
  metadata : ResultMetadata
} derive(Debug, Eq)

///|
pub fn ToolResult::success(content : Array[ContentBlock]) -> ToolResult {
  {
    content,
    structured_content: None,
    is_error: Some(false),
    metadata: ResultMetadata::empty(),
  }
}

///|
pub fn ToolResult::text(text : String) -> ToolResult {
  ToolResult::success([ContentBlock::text(text)])
}

///|
pub fn ToolResult::error(message : String) -> ToolResult {
  { ..ToolResult::text(message), is_error: Some(true), }
}

///|
/// Structured outputs may be any JSON value, including explicit null.
///
/// ```mbt check
/// test {
///   let result = @types.ToolResult::structured(Json::null())
///   assert_eq(result.structured_content, Some(Json::null()))
///   assert_eq(result.to_json(), {
///     "content": [],
///     "structuredContent": null,
///     "isError": false,
///   })
/// }
/// ```
pub fn ToolResult::structured(
  value : Json,
  content? : Array[ContentBlock] = [],
) -> ToolResult {
  { ..ToolResult::success(content), structured_content: Some(value), }
}

///|
pub fn ToolResult::from_json(value : Json) -> ToolResult raise MCPError {
  let fields = wire_object(value)
  let content = match fields.get("content") {
    Some(Array(values)) => values.map(ContentBlock::from_json)
    _ => raise InvalidParams("Missing or invalid tool content array")
  }
  {
    content,
    structured_content: fields.get("structuredContent"),
    is_error: wire_optional_bool(fields, "isError"),
    metadata: ResultMetadata::from_json(value, body_fields=[
      "content", "structuredContent", "isError",
    ]),
  }
}

///|
pub impl ToJson for ToolResult with fn to_json(self) {
  let fields = wire_extensions(self.metadata.to_fields(), [
    "content", "structuredContent", "isError",
  ])
  fields.set("content", Json::array(self.content.map(ContentBlock::to_json)))
  match self.structured_content {
    Some(value) => fields.set("structuredContent", value)
    None => ()
  }
  wire_put_bool(fields, "isError", self.is_error)
  Json::object(fields)
}

///|
pub extend ToolResult with Eq::{equal, not_equal}

///|
pub extend ToolResult with Debug::{to_repr}

///|
pub extend ToolResult with ToJson::{to_json}
