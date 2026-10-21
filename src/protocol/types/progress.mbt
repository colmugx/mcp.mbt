///|
/// Opaque progress identifier. Numeric tokens are not coerced to strings or integers.
pub(all) enum ProgressToken {
  String(String)
  Number(Double)
  ExactNumber(JsonNumber)
} derive(Debug)

///|
pub fn ProgressToken::from_json(value : Json) -> ProgressToken raise MCPError {
  match value {
    String(value) => ProgressToken::String(value)
    Number(_, ..) => ProgressToken::ExactNumber(JsonNumber::from_json(value))
    _ => raise InvalidParams("Progress token must be a string or number")
  }
}

///|
pub impl ToJson for ProgressToken with fn to_json(self) {
  match self {
    String(value) => Json::string(value)
    Number(value) => Json::number(value)
    ExactNumber(value) => value.to_json()
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
  {
    progress_token: token,
    progress: wire_exact_number(fields, "progress"),
    total: wire_optional_exact_number(fields, "total"),
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
  fields.set("progress", self.progress.to_json())
  wire_put_exact_number(fields, "total", self.total)
  wire_put_string(fields, "message", self.message)
  Json::object(fields)
}

///|
pub extend ProgressToken with ToJson::{to_json}

///|
pub impl Eq for ProgressToken with fn equal(self, other) {
  match (self, other) {
    (String(left), String(right)) => left == right
    (String(_), _) | (_, String(_)) => false
    _ => {
      let left = JsonNumber::from_json(self.to_json()) catch {
        _ => return false
      }
      let right = JsonNumber::from_json(other.to_json()) catch {
        _ => return false
      }
      left == right
    }
  }
}

///|
pub extend ProgressToken with Eq::{equal, not_equal}

///|
pub extend ProgressToken with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProgressNotification with ToJson::{to_json}
