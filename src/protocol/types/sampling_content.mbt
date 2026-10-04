///|
pub(all) struct ToolUseContent {
  id : String
  name : String
  input : Map[String, Json]
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Debug, Eq)

///|
pub(all) struct ToolResultContent {
  tool_use_id : String
  content : Array[ContentBlock]
  structured_content : Json?
  is_error : Bool?
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Debug, Eq)

///|
/// Sampling has a narrower standard union than tool-result content, plus tool-use blocks.
pub(all) enum SamplingContentBlock {
  Content(ContentBlock)
  ToolUse(ToolUseContent)
  ToolResult(ToolResultContent)
  Unknown(Json)
} derive(Debug, Eq)

///|
/// Retains single-block versus array presence on the wire, even for a one-element array.
pub(all) enum SamplingContent {
  Single(SamplingContentBlock)
  Multiple(Array[SamplingContentBlock])
} derive(Debug, Eq)

///|
pub fn ToolUseContent::new(
  id : String,
  name : String,
  input : Map[String, Json],
  meta? : Map[String, Json],
) -> ToolUseContent {
  { id, name, input, meta, extensions: Map([]), }
}

///|
pub fn ToolUseContent::from_json(value : Json) -> ToolUseContent raise MCPError {
  let fields = wire_object(value)
  guard wire_string(fields, "type") == "tool_use" else {
    raise InvalidParams("Expected tool_use content")
  }
  let input = match fields.get("input") {
    Some(Object(input)) => input.copy()
    _ => raise InvalidParams("Tool use input must be an object")
  }
  {
    id: wire_string(fields, "id"),
    name: wire_string(fields, "name"),
    input,
    meta: wire_optional_object(fields, "_meta"),
    extensions: wire_extensions(fields, ["type", "id", "name", "input", "_meta"]),
  }
}

///|
pub impl ToJson for ToolUseContent with fn to_json(self) {
  let fields = wire_extensions(self.extensions, [
    "type", "id", "name", "input", "_meta",
  ])
  fields.set("type", Json::string("tool_use"))
  fields.set("id", Json::string(self.id))
  fields.set("name", Json::string(self.name))
  fields.set("input", Json::object(self.input.copy()))
  wire_put_meta(fields, self.meta)
  Json::object(fields)
}

///|
pub fn ToolResultContent::new(
  tool_use_id : String,
  content : Array[ContentBlock],
  structured_content? : Json,
  is_error? : Bool,
  meta? : Map[String, Json],
) -> ToolResultContent {
  {
    tool_use_id,
    content,
    structured_content,
    is_error,
    meta,
    extensions: Map([]),
  }
}

///|
pub fn ToolResultContent::from_json(
  value : Json,
) -> ToolResultContent raise MCPError {
  let fields = wire_object(value)
  guard wire_string(fields, "type") == "tool_result" else {
    raise InvalidParams("Expected tool_result content")
  }
  let content = match fields.get("content") {
    Some(Array(content)) => content.map(ContentBlock::from_json)
    _ => raise InvalidParams("Tool result content must be an array")
  }
  {
    tool_use_id: wire_string(fields, "toolUseId"),
    content,
    structured_content: fields.get("structuredContent"),
    is_error: wire_optional_bool(fields, "isError"),
    meta: wire_optional_object(fields, "_meta"),
    extensions: wire_extensions(fields, [
      "type", "toolUseId", "content", "structuredContent", "isError", "_meta",
    ]),
  }
}

///|
pub impl ToJson for ToolResultContent with fn to_json(self) {
  let fields = wire_extensions(self.extensions, [
    "type", "toolUseId", "content", "structuredContent", "isError", "_meta",
  ])
  fields.set("type", Json::string("tool_result"))
  fields.set("toolUseId", Json::string(self.tool_use_id))
  fields.set("content", self.content.to_json())
  match self.structured_content {
    Some(value) => fields.set("structuredContent", value)
    None => ()
  }
  wire_put_bool(fields, "isError", self.is_error)
  wire_put_meta(fields, self.meta)
  Json::object(fields)
}

///|
pub fn SamplingContentBlock::from_json(
  value : Json,
) -> SamplingContentBlock raise MCPError {
  let fields = wire_object(value)
  match wire_string(fields, "type") {
    "text" | "image" | "audio" => Content(ContentBlock::from_json(value))
    "tool_use" => ToolUse(ToolUseContent::from_json(value))
    "tool_result" => ToolResult(ToolResultContent::from_json(value))
    "resource" | "resource_link" =>
      raise InvalidParams(
        "Resource content is only allowed inside a sampling tool_result",
      )
    _ => Unknown(value)
  }
}

///|
pub impl ToJson for SamplingContentBlock with fn to_json(self) {
  match self {
    Content(value) => value.to_json()
    ToolUse(value) => value.to_json()
    ToolResult(value) => value.to_json()
    Unknown(value) => value
  }
}

///|
pub fn SamplingContent::text(value : String) -> SamplingContent {
  Single(Content(ContentBlock::text(value)))
}

///|
pub fn SamplingContent::from_json(
  value : Json,
) -> SamplingContent raise MCPError {
  match value {
    Array(values) => Multiple(values.map(SamplingContentBlock::from_json))
    _ => Single(SamplingContentBlock::from_json(value))
  }
}

///|
pub impl ToJson for SamplingContent with fn to_json(self) {
  match self {
    Single(value) => value.to_json()
    Multiple(values) => values.to_json()
  }
}

///|
pub extend ToolUseContent with ToJson::{to_json}

///|
pub extend ToolUseContent with Eq::{equal, not_equal}

///|
pub extend ToolUseContent with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ToolResultContent with ToJson::{to_json}

///|
pub extend ToolResultContent with Eq::{equal, not_equal}

///|
pub extend ToolResultContent with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SamplingContentBlock with ToJson::{to_json}

///|
pub extend SamplingContentBlock with Eq::{equal, not_equal}

///|
pub extend SamplingContentBlock with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SamplingContent with ToJson::{to_json}

///|
pub extend SamplingContent with Eq::{equal, not_equal}

///|
pub extend SamplingContent with @moonbitlang/core/debug.Debug::{to_repr}
