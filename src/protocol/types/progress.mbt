///|
/// Opaque progress identifier. Numeric tokens are not coerced to strings or integers.
pub(all) enum ProgressToken {
  String(String)
  Number(Double)
} derive(Debug, Eq)

///|
pub fn ProgressToken::from_json(value : Json) -> ProgressToken raise MCPError {
  match value {
    String(value) => ProgressToken::String(value)
    Number(value, ..) => {
      guard !value.is_nan() && !value.is_inf() else {
        raise InvalidParams("Progress token must be a finite number")
      }
      ProgressToken::Number(value)
    }
    _ => raise InvalidParams("Progress token must be a string or number")
  }
}

///|
pub impl ToJson for ProgressToken with fn to_json(self) {
  match self {
    String(value) => Json::string(value)
    Number(value) => Json::number(value)
  }
}

///|
pub fn ProgressNotification::from_json(
  value : Json,
) -> ProgressNotification raise MCPError {
  let fields = wire_object(value)
  let token = match fields.get("progressToken") {
    Some(value) => ProgressToken::from_json(value)
    None => raise InvalidParams("Missing progressToken")
  }
  let progress = match fields.get("progress") {
    Some(Number(value, ..)) if !value.is_nan() && !value.is_inf() => value
    _ => raise InvalidParams("Progress must be a finite number")
  }
  let total = match fields.get("total") {
    None => None
    Some(Number(value, ..)) if !value.is_nan() && !value.is_inf() => Some(value)
    _ => raise InvalidParams("Progress total must be a finite number")
  }
  {
    progress_token: token,
    progress,
    total,
    message: wire_optional_string(fields, "message"),
    extra_fields: wire_extensions(fields, [
      "progressToken", "progress", "total", "message",
    ]),
  }
}

///|
pub impl ToJson for ProgressNotification with fn to_json(self) {
  let fields = self.extra_fields.copy()
  fields.set("progressToken", self.progress_token.to_json())
  fields.set("progress", Json::number(self.progress))
  match self.total {
    Some(value) => fields.set("total", Json::number(value))
    None => ()
  }
  wire_put_string(fields, "message", self.message)
  Json::object(fields)
}

///|
pub extend ProgressToken with ToJson::{to_json}

///|
pub extend ProgressToken with Eq::{equal, not_equal}

///|
pub extend ProgressToken with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProgressNotification with ToJson::{to_json}
