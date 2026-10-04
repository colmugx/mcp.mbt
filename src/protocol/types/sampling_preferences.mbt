///|
pub(all) struct ModelHint {
  name : String?
  extensions : Map[String, Json]
} derive(Debug, Eq)

///|
pub(all) struct ModelPreferences {
  hints : Array[ModelHint]?
  cost_priority : Double?
  speed_priority : Double?
  intelligence_priority : Double?
  extensions : Map[String, Json]
} derive(Debug, Eq)

///|
pub(all) enum SamplingContext {
  NoContext
  ThisServer
  AllServers
} derive(Debug, Eq)

///|
pub(all) enum ToolChoiceMode {
  Auto
  Required
  Disabled
} derive(Debug, Eq)

///|
pub(all) struct ToolChoice {
  mode : ToolChoiceMode?
  extensions : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn ModelHint::new(name? : String) -> ModelHint {
  { name, extensions: Map([]), }
}

///|
pub fn ModelHint::from_json(value : Json) -> ModelHint raise MCPError {
  let fields = wire_object(value)
  {
    name: wire_optional_string(fields, "name"),
    extensions: wire_extensions(fields, ["name"]),
  }
}

///|
pub impl ToJson for ModelHint with fn to_json(self) {
  let fields = wire_extensions(self.extensions, ["name"])
  wire_put_string(fields, "name", self.name)
  Json::object(fields)
}

///|
pub fn ModelPreferences::new(
  hints? : Array[ModelHint],
  cost_priority? : Double,
  speed_priority? : Double,
  intelligence_priority? : Double,
) -> ModelPreferences {
  {
    hints,
    cost_priority,
    speed_priority,
    intelligence_priority,
    extensions: Map([]),
  }
}

///|
fn sampling_priority(
  fields : Map[String, Json],
  key : String,
) -> Double? raise MCPError {
  let value = wire_optional_number(fields, key)
  match value {
    Some(value) if value < 0 || value > 1 =>
      raise InvalidParams("Sampling '\{key}' must be between 0 and 1")
    _ => value
  }
}

///|
pub fn ModelPreferences::from_json(
  value : Json,
) -> ModelPreferences raise MCPError {
  let fields = wire_object(value)
  let hints = match fields.get("hints") {
    None => None
    Some(Array(values)) => Some(values.map(ModelHint::from_json))
    _ => raise InvalidParams("Model hints must be an array")
  }
  {
    hints,
    cost_priority: sampling_priority(fields, "costPriority"),
    speed_priority: sampling_priority(fields, "speedPriority"),
    intelligence_priority: sampling_priority(fields, "intelligencePriority"),
    extensions: wire_extensions(fields, [
      "hints", "costPriority", "speedPriority", "intelligencePriority",
    ]),
  }
}

///|
pub impl ToJson for ModelPreferences with fn to_json(self) {
  let fields = wire_extensions(self.extensions, [
    "hints", "costPriority", "speedPriority", "intelligencePriority",
  ])
  match self.hints {
    Some(hints) => fields.set("hints", hints.to_json())
    None => ()
  }
  wire_put_number(fields, "costPriority", self.cost_priority)
  wire_put_number(fields, "speedPriority", self.speed_priority)
  wire_put_number(fields, "intelligencePriority", self.intelligence_priority)
  Json::object(fields)
}

///|
pub fn SamplingContext::from_json(
  value : Json,
) -> SamplingContext raise MCPError {
  match value {
    String("none") => NoContext
    String("thisServer") => ThisServer
    String("allServers") => AllServers
    _ => raise InvalidParams("Invalid sampling includeContext")
  }
}

///|
pub impl ToJson for SamplingContext with fn to_json(self) {
  Json::string(
    match self {
      NoContext => "none"
      ThisServer => "thisServer"
      AllServers => "allServers"
    },
  )
}

///|
pub fn ToolChoiceMode::from_json(value : Json) -> ToolChoiceMode raise MCPError {
  match value {
    String("auto") => Auto
    String("required") => Required
    String("none") => ToolChoiceMode::Disabled
    _ => raise InvalidParams("Invalid sampling tool choice mode")
  }
}

///|
pub impl ToJson for ToolChoiceMode with fn to_json(self) {
  Json::string(
    match self {
      Auto => "auto"
      Required => "required"
      ToolChoiceMode::Disabled => "none"
    },
  )
}

///|
pub fn ToolChoice::new(mode? : ToolChoiceMode) -> ToolChoice {
  { mode, extensions: Map([]), }
}

///|
pub fn ToolChoice::from_json(value : Json) -> ToolChoice raise MCPError {
  let fields = wire_object(value)
  {
    mode: fields.get("mode").map(ToolChoiceMode::from_json),
    extensions: wire_extensions(fields, ["mode"]),
  }
}

///|
pub impl ToJson for ToolChoice with fn to_json(self) {
  let fields = wire_extensions(self.extensions, ["mode"])
  match self.mode {
    Some(mode) => fields.set("mode", mode.to_json())
    None => ()
  }
  Json::object(fields)
}

///|
pub extend ModelHint with ToJson::{to_json}

///|
pub extend ModelHint with Eq::{equal, not_equal}

///|
pub extend ModelHint with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ModelPreferences with ToJson::{to_json}

///|
pub extend ModelPreferences with Eq::{equal, not_equal}

///|
pub extend ModelPreferences with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SamplingContext with ToJson::{to_json}

///|
pub extend SamplingContext with Eq::{equal, not_equal}

///|
pub extend SamplingContext with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ToolChoiceMode with ToJson::{to_json}

///|
pub extend ToolChoiceMode with Eq::{equal, not_equal}

///|
pub extend ToolChoiceMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ToolChoice with ToJson::{to_json}

///|
pub extend ToolChoice with Eq::{equal, not_equal}

///|
pub extend ToolChoice with @moonbitlang/core/debug.Debug::{to_repr}
