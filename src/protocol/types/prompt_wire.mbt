///|
pub fn PromptArgument::new(
  name : String,
  title? : String,
  description? : String,
  required? : Bool,
) -> PromptArgument {
  { name, title, description, required, extensions: Map([]), }
}

///|
pub fn PromptArgument::from_json(value : Json) -> PromptArgument raise MCPError {
  let fields = wire_object(value)
  {
    name: wire_string(fields, "name"),
    title: wire_optional_string(fields, "title"),
    description: wire_optional_string(fields, "description"),
    required: wire_optional_bool(fields, "required"),
    extensions: wire_extensions(fields, [
      "name", "title", "description", "required",
    ]),
  }
}

///|
pub impl ToJson for PromptArgument with fn to_json(self) {
  let fields = wire_extensions(self.extensions, [
    "name", "title", "description", "required",
  ])
  fields.set("name", Json::string(self.name))
  wire_put_string(fields, "title", self.title)
  wire_put_string(fields, "description", self.description)
  wire_put_bool(fields, "required", self.required)
  Json::object(fields)
}

///|
pub(all) struct PromptDefinition {
  name : String
  title : String?
  description : String?
  arguments : Array[PromptArgument]?
  icons : Array[Icon]?
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn PromptDefinition::new(
  name : String,
  title? : String,
  description? : String,
  arguments? : Array[PromptArgument],
  icons? : Array[Icon],
  meta? : Map[String, Json],
) -> PromptDefinition {
  { name, title, description, arguments, icons, meta, extensions: Map([]), }
}

///|
pub fn PromptDefinition::from_json(
  value : Json,
) -> PromptDefinition raise MCPError {
  let fields = wire_object(value)
  {
    name: wire_string(fields, "name"),
    title: wire_optional_string(fields, "title"),
    description: wire_optional_string(fields, "description"),
    arguments: match fields.get("arguments") {
      Some(Array(values)) => Some(values.map(PromptArgument::from_json))
      None => None
      _ => raise InvalidParams("Invalid prompt arguments array")
    },
    icons: match fields.get("icons") {
      Some(Array(values)) => Some(values.map(Icon::from_json))
      None => None
      _ => raise InvalidParams("Invalid prompt icons array")
    },
    meta: wire_optional_object(fields, "_meta"),
    extensions: wire_extensions(fields, [
      "name", "title", "description", "arguments", "icons", "_meta",
    ]),
  }
}

///|
pub impl ToJson for PromptDefinition with fn to_json(self) {
  let fields = wire_extensions(self.extensions, [
    "name", "title", "description", "arguments", "icons", "_meta",
  ])
  fields.set("name", Json::string(self.name))
  wire_put_string(fields, "title", self.title)
  wire_put_string(fields, "description", self.description)
  match self.arguments {
    Some(values) =>
      fields.set("arguments", Json::array(values.map(PromptArgument::to_json)))
    None => ()
  }
  match self.icons {
    Some(values) => fields.set("icons", Json::array(values.map(Icon::to_json)))
    None => ()
  }
  wire_put_meta(fields, self.meta)
  Json::object(fields)
}

///|
pub fn PromptMessage::new(role : Role, content : ContentBlock) -> PromptMessage {
  let role = match role {
    User => "user"
    Assistant => "assistant"
  }
  { role, content, extensions: Map([]), }
}

///|
pub fn PromptMessage::from_json(value : Json) -> PromptMessage raise MCPError {
  let fields = wire_object(value)
  let role = wire_string(fields, "role")
  guard role == "user" || role == "assistant" else {
    raise InvalidParams("Invalid prompt message role")
  }
  let content = match fields.get("content") {
    Some(value) => ContentBlock::from_json(value)
    None => raise InvalidParams("Missing prompt message content")
  }
  { role, content, extensions: wire_extensions(fields, ["role", "content"]), }
}

///|
pub impl ToJson for PromptMessage with fn to_json(self) {
  let fields = wire_extensions(self.extensions, ["role", "content"])
  fields.set("role", Json::string(self.role))
  fields.set("content", self.content.to_json())
  Json::object(fields)
}

///|
pub fn GetPromptResult::new(
  messages : Array[PromptMessage],
  description? : String,
  metadata? : ResultMetadata = ResultMetadata::empty(),
) -> GetPromptResult {
  { messages, description, metadata, }
}

///|
pub fn GetPromptResult::from_json(
  value : Json,
) -> GetPromptResult raise MCPError {
  let fields = wire_object(value)
  let messages = match fields.get("messages") {
    Some(Array(values)) => values.map(PromptMessage::from_json)
    _ => raise InvalidParams("Missing or invalid prompt messages array")
  }
  {
    messages,
    description: wire_optional_string(fields, "description"),
    metadata: ResultMetadata::from_json(value, body_fields=[
      "description", "messages",
    ]),
  }
}

///|
pub impl ToJson for GetPromptResult with fn to_json(self) {
  let fields = wire_extensions(self.metadata.to_fields(), [
    "description", "messages",
  ])
  fields.set("messages", Json::array(self.messages.map(PromptMessage::to_json)))
  wire_put_string(fields, "description", self.description)
  Json::object(fields)
}

///|
pub extend PromptArgument with ToJson::{to_json}

///|
pub extend PromptDefinition with Eq::{equal, not_equal}

///|
pub extend PromptDefinition with Debug::{to_repr}

///|
pub extend PromptDefinition with ToJson::{to_json}

///|
pub extend PromptMessage with ToJson::{to_json}

///|
pub extend GetPromptResult with ToJson::{to_json}
