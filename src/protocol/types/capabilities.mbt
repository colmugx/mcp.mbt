///|
fn capability_object_map(
  fields : Map[String, Json],
  key : String,
) -> Map[String, Json]? raise MCPError {
  let values = wire_optional_object(fields, key)
  match values {
    Some(values) =>
      for name, value in values {
        guard value is Object(_) else {
          raise InvalidParams("Capability '\{key}.\{name}' must be an object")
        }
      }
    None => ()
  }
  values
}

///|
fn capability_put_object(
  fields : Map[String, Json],
  key : String,
  value : Map[String, Json]?,
) -> Unit {
  match value {
    Some(value) => fields.set(key, Json::object(value.copy()))
    None => ()
  }
}

///|
pub fn ClientCapabilities::new(
  experimental? : Map[String, Json],
  roots? : RootCapabilities,
  sampling? : SamplingCapabilities,
  elicitation? : ElicitationCapabilities,
  extensions? : Map[String, Json],
) -> ClientCapabilities {
  { experimental, roots, sampling, elicitation, extensions, extra_fields: {}, }
}

///|
pub fn ClientCapabilities::from_json(
  value : Json,
) -> ClientCapabilities raise MCPError {
  let fields = wire_object(value)
  {
    experimental: capability_object_map(fields, "experimental"),
    roots: fields.get("roots").map(RootCapabilities::from_json),
    sampling: fields.get("sampling").map(SamplingCapabilities::from_json),
    elicitation: fields
    .get("elicitation")
    .map(ElicitationCapabilities::from_json),
    extensions: capability_object_map(fields, "extensions"),
    extra_fields: wire_extensions(fields, [
      "experimental", "roots", "sampling", "elicitation", "extensions",
    ]),
  }
}

///|
pub impl ToJson for ClientCapabilities with fn to_json(self) {
  let fields = wire_extensions(self.extra_fields, [
    "experimental", "roots", "sampling", "elicitation", "extensions",
  ])
  capability_put_object(fields, "experimental", self.experimental)
  capability_put_object(fields, "extensions", self.extensions)
  match self.roots {
    Some(value) => fields.set("roots", value.to_json())
    None => ()
  }
  match self.sampling {
    Some(value) => fields.set("sampling", value.to_json())
    None => ()
  }
  match self.elicitation {
    Some(value) => fields.set("elicitation", value.to_json())
    None => ()
  }
  Json::object(fields)
}

///|
pub fn RootCapabilities::new(list_changed? : Bool) -> RootCapabilities {
  { list_changed, extra_fields: {}, }
}

///|
pub fn RootCapabilities::from_json(
  value : Json,
) -> RootCapabilities raise MCPError {
  let fields = wire_object(value)
  {
    list_changed: wire_optional_bool(fields, "listChanged"),
    extra_fields: wire_extensions(fields, ["listChanged"]),
  }
}

///|
pub impl ToJson for RootCapabilities with fn to_json(self) {
  let fields = wire_extensions(self.extra_fields, ["listChanged"])
  wire_put_bool(fields, "listChanged", self.list_changed)
  Json::object(fields)
}

///|
pub fn SamplingCapabilities::new(
  context? : Map[String, Json],
  tools? : Map[String, Json],
) -> SamplingCapabilities {
  { context, tools, extra_fields: {}, }
}

///|
pub fn SamplingCapabilities::from_json(
  value : Json,
) -> SamplingCapabilities raise MCPError {
  let fields = wire_object(value)
  {
    context: wire_optional_object(fields, "context"),
    tools: wire_optional_object(fields, "tools"),
    extra_fields: wire_extensions(fields, ["context", "tools"]),
  }
}

///|
pub impl ToJson for SamplingCapabilities with fn to_json(self) {
  let fields = wire_extensions(self.extra_fields, ["context", "tools"])
  capability_put_object(fields, "context", self.context)
  capability_put_object(fields, "tools", self.tools)
  Json::object(fields)
}

///|
pub fn ElicitationCapabilities::new(
  form? : Map[String, Json],
  url? : Map[String, Json],
) -> ElicitationCapabilities {
  { form, url, extra_fields: {}, }
}

///|
pub fn ElicitationCapabilities::from_json(
  value : Json,
) -> ElicitationCapabilities raise MCPError {
  let fields = wire_object(value)
  {
    form: wire_optional_object(fields, "form"),
    url: wire_optional_object(fields, "url"),
    extra_fields: wire_extensions(fields, ["form", "url"]),
  }
}

///|
pub impl ToJson for ElicitationCapabilities with fn to_json(self) {
  let fields = wire_extensions(self.extra_fields, ["form", "url"])
  capability_put_object(fields, "form", self.form)
  capability_put_object(fields, "url", self.url)
  Json::object(fields)
}

///|
pub fn ServerCapabilities::new(
  experimental? : Map[String, Json],
  logging? : Map[String, Json],
  completions? : Map[String, Json],
  tools? : ToolCapabilities,
  resources? : ResourceCapabilities,
  prompts? : PromptCapabilities,
  extensions? : Map[String, Json],
) -> ServerCapabilities {
  {
    experimental,
    logging,
    completions,
    tools,
    resources,
    prompts,
    extensions,
    extra_fields: {},
  }
}

///|
pub fn ServerCapabilities::from_json(
  value : Json,
) -> ServerCapabilities raise MCPError {
  let fields = wire_object(value)
  {
    experimental: capability_object_map(fields, "experimental"),
    logging: wire_optional_object(fields, "logging"),
    completions: wire_optional_object(fields, "completions"),
    tools: fields.get("tools").map(ToolCapabilities::from_json),
    resources: fields.get("resources").map(ResourceCapabilities::from_json),
    prompts: fields.get("prompts").map(PromptCapabilities::from_json),
    extensions: capability_object_map(fields, "extensions"),
    extra_fields: wire_extensions(fields, [
      "experimental", "logging", "completions", "tools", "resources", "prompts",
      "extensions",
    ]),
  }
}

///|
pub impl ToJson for ServerCapabilities with fn to_json(self) {
  let fields = wire_extensions(self.extra_fields, [
    "experimental", "logging", "completions", "tools", "resources", "prompts", "extensions",
  ])
  capability_put_object(fields, "experimental", self.experimental)
  capability_put_object(fields, "logging", self.logging)
  capability_put_object(fields, "completions", self.completions)
  capability_put_object(fields, "extensions", self.extensions)
  match self.tools {
    Some(value) => fields.set("tools", value.to_json())
    None => ()
  }
  match self.resources {
    Some(value) => fields.set("resources", value.to_json())
    None => ()
  }
  match self.prompts {
    Some(value) => fields.set("prompts", value.to_json())
    None => ()
  }
  Json::object(fields)
}

///|
pub fn ToolCapabilities::new(list_changed? : Bool) -> ToolCapabilities {
  { list_changed, extra_fields: {}, }
}

///|
pub fn ToolCapabilities::from_json(
  value : Json,
) -> ToolCapabilities raise MCPError {
  let fields = wire_object(value)
  {
    list_changed: wire_optional_bool(fields, "listChanged"),
    extra_fields: wire_extensions(fields, ["listChanged"]),
  }
}

///|
pub impl ToJson for ToolCapabilities with fn to_json(self) {
  let fields = wire_extensions(self.extra_fields, ["listChanged"])
  wire_put_bool(fields, "listChanged", self.list_changed)
  Json::object(fields)
}

///|
pub fn PromptCapabilities::new(list_changed? : Bool) -> PromptCapabilities {
  { list_changed, extra_fields: {}, }
}

///|
pub fn PromptCapabilities::from_json(
  value : Json,
) -> PromptCapabilities raise MCPError {
  let fields = wire_object(value)
  {
    list_changed: wire_optional_bool(fields, "listChanged"),
    extra_fields: wire_extensions(fields, ["listChanged"]),
  }
}

///|
pub impl ToJson for PromptCapabilities with fn to_json(self) {
  let fields = wire_extensions(self.extra_fields, ["listChanged"])
  wire_put_bool(fields, "listChanged", self.list_changed)
  Json::object(fields)
}

///|
pub fn ResourceCapabilities::new(
  subscribe? : Bool,
  list_changed? : Bool,
) -> ResourceCapabilities {
  { subscribe, list_changed, extra_fields: {}, }
}

///|
pub fn ResourceCapabilities::from_json(
  value : Json,
) -> ResourceCapabilities raise MCPError {
  let fields = wire_object(value)
  {
    subscribe: wire_optional_bool(fields, "subscribe"),
    list_changed: wire_optional_bool(fields, "listChanged"),
    extra_fields: wire_extensions(fields, ["subscribe", "listChanged"]),
  }
}

///|
pub impl ToJson for ResourceCapabilities with fn to_json(self) {
  let fields = wire_extensions(self.extra_fields, ["subscribe", "listChanged"])
  wire_put_bool(fields, "subscribe", self.subscribe)
  wire_put_bool(fields, "listChanged", self.list_changed)
  Json::object(fields)
}

///|
pub extend ClientCapabilities with ToJson::{to_json}

///|
pub extend ServerCapabilities with ToJson::{to_json}

///|
pub extend RootCapabilities with ToJson::{to_json}

///|
pub extend SamplingCapabilities with ToJson::{to_json}

///|
pub extend ElicitationCapabilities with ToJson::{to_json}

///|
pub extend ToolCapabilities with ToJson::{to_json}

///|
pub extend ResourceCapabilities with ToJson::{to_json}

///|
pub extend PromptCapabilities with ToJson::{to_json}
