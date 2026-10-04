///|
pub fn SamplingMessage::new(
  role : Role,
  content : SamplingContent,
  meta? : Map[String, Json],
) -> SamplingMessage {
  { role, content, meta, extensions: Map([]), }
}

///|
pub fn SamplingMessage::from_json(
  value : Json,
) -> SamplingMessage raise MCPError {
  let fields = wire_object(value)
  let role = match fields.get("role") {
    Some(value) => Role::from_json(value)
    None => raise InvalidParams("Missing sampling role")
  }
  let content = match fields.get("content") {
    Some(value) => SamplingContent::from_json(value)
    None => raise InvalidParams("Missing sampling content")
  }
  {
    role,
    content,
    meta: wire_optional_object(fields, "_meta"),
    extensions: wire_extensions(fields, ["role", "content", "_meta"]),
  }
}

///|
pub impl ToJson for SamplingMessage with fn to_json(self) {
  let fields = wire_extensions(self.extensions, ["role", "content", "_meta"])
  fields.set("role", self.role.to_json())
  fields.set("content", self.content.to_json())
  wire_put_meta(fields, self.meta)
  Json::object(fields)
}

///|
pub fn CreateMessageRequest::new(
  messages : Array[SamplingMessage],
  max_tokens : Double,
  model_preferences? : ModelPreferences,
  system_prompt? : String,
  include_context? : SamplingContext,
  temperature? : Double,
  stop_sequences? : Array[String],
  metadata? : Map[String, Json],
  tools? : Array[ToolDefinition],
  tool_choice? : ToolChoice,
) -> CreateMessageRequest {
  {
    messages,
    max_tokens,
    model_preferences,
    system_prompt,
    include_context,
    temperature,
    stop_sequences,
    metadata,
    tools,
    tool_choice,
    extensions: Map([]),
  }
}

///|
pub fn CreateMessageRequest::from_json(
  value : Json,
) -> CreateMessageRequest raise MCPError {
  let fields = wire_object(value)
  let messages = match fields.get("messages") {
    Some(Array(values)) => values.map(SamplingMessage::from_json)
    _ => raise InvalidParams("Sampling messages must be an array")
  }
  let tools = match fields.get("tools") {
    None => None
    Some(Array(values)) => Some(values.map(ToolDefinition::from_json))
    _ => raise InvalidParams("Sampling tools must be an array")
  }
  {
    messages,
    max_tokens: wire_number(fields, "maxTokens"),
    model_preferences: fields
    .get("modelPreferences")
    .map(ModelPreferences::from_json),
    system_prompt: wire_optional_string(fields, "systemPrompt"),
    include_context: fields
    .get("includeContext")
    .map(SamplingContext::from_json),
    temperature: wire_optional_number(fields, "temperature"),
    stop_sequences: wire_optional_strings(fields, "stopSequences"),
    metadata: wire_optional_object(fields, "metadata"),
    tools,
    tool_choice: fields.get("toolChoice").map(ToolChoice::from_json),
    extensions: wire_extensions(fields, [
      "messages", "maxTokens", "modelPreferences", "systemPrompt", "includeContext",
      "temperature", "stopSequences", "metadata", "tools", "toolChoice",
    ]),
  }
}

///|
pub impl ToJson for CreateMessageRequest with fn to_json(self) {
  let fields = wire_extensions(self.extensions, [
    "messages", "maxTokens", "modelPreferences", "systemPrompt", "includeContext",
    "temperature", "stopSequences", "metadata", "tools", "toolChoice",
  ])
  fields.set("messages", self.messages.to_json())
  fields.set("maxTokens", Json::number(self.max_tokens))
  match self.model_preferences {
    Some(value) => fields.set("modelPreferences", value.to_json())
    None => ()
  }
  wire_put_string(fields, "systemPrompt", self.system_prompt)
  match self.include_context {
    Some(value) => fields.set("includeContext", value.to_json())
    None => ()
  }
  wire_put_number(fields, "temperature", self.temperature)
  match self.stop_sequences {
    Some(value) => fields.set("stopSequences", value.to_json())
    None => ()
  }
  match self.metadata {
    Some(value) => fields.set("metadata", Json::object(value.copy()))
    None => ()
  }
  match self.tools {
    Some(value) => fields.set("tools", value.to_json())
    None => ()
  }
  match self.tool_choice {
    Some(value) => fields.set("toolChoice", value.to_json())
    None => ()
  }
  Json::object(fields)
}

///|
pub fn CreateMessageResult::new(
  role : Role,
  model : String,
  content : SamplingContent,
  stop_reason? : String,
  meta? : Map[String, Json],
) -> CreateMessageResult {
  { role, model, content, stop_reason, meta, extensions: Map([]), }
}

///|
pub fn CreateMessageResult::text(
  model : String,
  content : String,
  stop_reason? : String,
) -> CreateMessageResult {
  CreateMessageResult::new(
    Role::Assistant,
    model,
    SamplingContent::text(content),
    stop_reason?,
  )
}

///|
pub fn CreateMessageResult::from_json(
  value : Json,
) -> CreateMessageResult raise MCPError {
  let fields = wire_object(value)
  let message = SamplingMessage::from_json(value)
  {
    role: message.role,
    content: message.content,
    model: wire_string(fields, "model"),
    stop_reason: wire_optional_string(fields, "stopReason"),
    meta: message.meta,
    extensions: wire_extensions(fields, [
      "role", "model", "content", "stopReason", "_meta",
    ]),
  }
}

///|
pub impl ToJson for CreateMessageResult with fn to_json(self) {
  let fields = wire_extensions(self.extensions, [
    "role", "model", "content", "stopReason", "_meta",
  ])
  fields.set("role", self.role.to_json())
  fields.set("model", Json::string(self.model))
  fields.set("content", self.content.to_json())
  wire_put_string(fields, "stopReason", self.stop_reason)
  wire_put_meta(fields, self.meta)
  Json::object(fields)
}

///|
pub extend SamplingMessage with ToJson::{to_json}

///|
pub extend CreateMessageRequest with ToJson::{to_json}

///|
pub extend CreateMessageResult with ToJson::{to_json}
