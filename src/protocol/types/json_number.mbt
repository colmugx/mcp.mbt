///|
/// Exact JSON numeric identity and wire spelling, including fractional tokens.
/// This is not an arithmetic API; conversion to Double is explicitly lossy.
pub struct JsonNumber {
  wire : Json
  canonical : String
} derive(Debug)

///|
pub fn JsonNumber::from_json(value : Json) -> JsonNumber raise MCPError {
  guard value is Number(number, repr~) else {
    raise InvalidParams("Expected a JSON number")
  }
  let literal = match repr {
    Some(literal) => literal
    None => {
      guard !number.is_nan() && !number.is_inf() else {
        raise InvalidParams("Non-finite number has no JSON literal")
      }
      value.stringify()
    }
  }
  guard integer_key(literal, integer_only=false) is Some(canonical) else {
    raise InvalidParams("Invalid JSON number literal")
  }
  let decoded = @json.parse(literal) catch {
    _ => raise InvalidParams("Invalid JSON number representation")
  }
  guard decoded is Number(expected, ..) &&
    !number.is_nan() &&
    expected == number else {
    raise InvalidParams(
      "JSON number representation contradicts its numeric value",
    )
  }
  { wire: Json::number(number, repr=literal), canonical, }
}

///|
pub fn JsonNumber::from_literal(literal : String) -> JsonNumber raise MCPError {
  let parsed = @json.parse(literal) catch {
    _ => raise InvalidParams("Invalid JSON number literal")
  }
  guard parsed is Number(number, ..) else {
    raise InvalidParams("Expected a JSON number literal")
  }
  JsonNumber::from_json(Json::number(number, repr=literal))
}

///|
pub fn JsonNumber::to_json(self : JsonNumber) -> Json {
  self.wire
}

///|
pub fn JsonNumber::key(self : JsonNumber) -> String {
  self.canonical
}

///|
pub impl Eq for JsonNumber with fn equal(self, other) {
  self.canonical == other.canonical
}

///|
pub extend JsonNumber with Eq::{equal, not_equal}

///|
pub extend JsonNumber with @moonbitlang/core/debug.Debug::{to_repr}
