///|
pub(all) enum ElicitationAction {
  Accept
  Decline
  Cancel
} derive(Debug, Eq)

///|
pub(all) enum ElicitationValue {
  String(String)
  Number(Double)
  Boolean(Bool)
  Strings(Array[String])
} derive(Debug, Eq)

///|
pub fn ElicitationAction::from_json(
  value : Json,
) -> ElicitationAction raise MCPError {
  match value {
    String("accept") => Accept
    String("decline") => Decline
    String("cancel") => Cancel
    _ => raise InvalidParams("Invalid elicitation action")
  }
}

///|
pub impl ToJson for ElicitationAction with fn to_json(self) {
  Json::string(
    match self {
      Accept => "accept"
      Decline => "decline"
      Cancel => "cancel"
    },
  )
}

///|
pub fn ElicitationValue::from_json(
  value : Json,
) -> ElicitationValue raise MCPError {
  match value {
    String(value) => ElicitationValue::String(value)
    Number(value, ..) if !value.is_nan() && !value.is_inf() =>
      ElicitationValue::Number(value)
    True => ElicitationValue::Boolean(true)
    False => ElicitationValue::Boolean(false)
    Array(values) =>
      ElicitationValue::Strings(
        values.map(value => {
          match value {
            String(value) => value
            _ => raise InvalidParams("Elicitation arrays must contain strings")
          }
        }),
      )
    _ =>
      raise InvalidParams(
        "Elicitation content values must be strings, finite numbers, booleans or string arrays",
      )
  }
}

///|
pub impl ToJson for ElicitationValue with fn to_json(self) {
  match self {
    String(value) => Json::string(value)
    Number(value) => Json::number(value)
    Boolean(value) => Json::boolean(value)
    Strings(values) => values.to_json()
  }
}

///|
pub fn ElicitationRequest::form(
  message : String,
  requested_schema : Json,
  explicit_mode? : Bool = false,
  meta? : Map[String, Json],
) -> ElicitationRequest {
  Form(message, requested_schema~, explicit_mode~, meta~, extensions=Map([]))
}

///|
pub fn ElicitationRequest::url(
  message : String,
  url : String,
  elicitation_id? : String,
  meta? : Map[String, Json],
) -> ElicitationRequest {
  Url(message, url~, elicitation_id~, meta~, extensions=Map([]))
}

///|
pub fn ElicitationRequest::from_json(
  value : Json,
) -> ElicitationRequest raise MCPError {
  let fields = wire_object(value)
  let message = wire_string(fields, "message")
  let meta = wire_optional_object(fields, "_meta")
  match fields.get("mode") {
    None | Some(String("form")) => {
      let requested_schema = match fields.get("requestedSchema") {
        Some(Object(schema)) if schema.get("type") is Some(String("object")) =>
          Json::object(schema.copy())
        _ =>
          raise InvalidParams(
            "Elicitation form requestedSchema must have an object root",
          )
      }
      check_elicitation_schema(requested_schema)
      Form(
        message,
        requested_schema~,
        explicit_mode=fields.contains("mode"),
        meta~,
        extensions=wire_extensions(fields, [
          "message", "requestedSchema", "mode", "_meta",
        ]),
      )
    }
    Some(String("url")) =>
      Url(
        message,
        url=wire_string(fields, "url"),
        elicitation_id=wire_optional_string(fields, "elicitationId"),
        meta~,
        extensions=wire_extensions(fields, [
          "message", "mode", "url", "elicitationId", "_meta",
        ]),
      )
    _ => raise InvalidParams("Elicitation mode must be form or url")
  }
}

///|
pub impl ToJson for ElicitationRequest with fn to_json(self) {
  match self {
    Form(message, requested_schema~, explicit_mode~, meta~, extensions~) => {
      let fields = wire_extensions(extensions, [
        "message", "requestedSchema", "mode", "_meta",
      ])
      fields.set("message", Json::string(message))
      fields.set("requestedSchema", requested_schema)
      if explicit_mode {
        fields.set("mode", Json::string("form"))
      }
      wire_put_meta(fields, meta)
      Json::object(fields)
    }
    Url(message, url~, elicitation_id~, meta~, extensions~) => {
      let fields = wire_extensions(extensions, [
        "message", "mode", "url", "elicitationId", "_meta",
      ])
      fields.set("message", Json::string(message))
      fields.set("mode", Json::string("url"))
      fields.set("url", Json::string(url))
      wire_put_string(fields, "elicitationId", elicitation_id)
      wire_put_meta(fields, meta)
      Json::object(fields)
    }
  }
}

///|
pub fn ElicitationResult::new(
  action : ElicitationAction,
  content? : Map[String, ElicitationValue],
) -> ElicitationResult {
  { action, content, extensions: Map([]), }
}

///|
pub fn ElicitationResult::from_json(
  value : Json,
) -> ElicitationResult raise MCPError {
  let fields = wire_object(value)
  let action = match fields.get("action") {
    Some(value) => ElicitationAction::from_json(value)
    None => raise InvalidParams("Missing elicitation action")
  }
  let content = match fields.get("content") {
    None => None
    Some(Object(values)) => {
      let decoded : Map[String, ElicitationValue] = Map([])
      for key, value in values {
        decoded.set(key, ElicitationValue::from_json(value))
      }
      Some(decoded)
    }
    _ => raise InvalidParams("Elicitation content must be an object")
  }
  {
    action,
    content,
    extensions: wire_extensions(fields, ["action", "content"]),
  }
}

///|
pub impl ToJson for ElicitationResult with fn to_json(self) {
  let fields = wire_extensions(self.extensions, ["action", "content"])
  fields.set("action", self.action.to_json())
  match self.content {
    Some(content) => {
      let values : Map[String, Json] = Map([])
      for key, value in content {
        values.set(key, value.to_json())
      }
      fields.set("content", Json::object(values))
    }
    None => ()
  }
  Json::object(fields)
}

///|
pub extend ElicitationAction with ToJson::{to_json}

///|
pub extend ElicitationAction with Eq::{equal, not_equal}

///|
pub extend ElicitationAction with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ElicitationValue with ToJson::{to_json}

///|
pub extend ElicitationValue with Eq::{equal, not_equal}

///|
pub extend ElicitationValue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ElicitationRequest with ToJson::{to_json}

///|
pub extend ElicitationResult with ToJson::{to_json}
