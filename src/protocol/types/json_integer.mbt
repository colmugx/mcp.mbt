///|
/// A mathematical JSON integer retaining its wire literal, without an Int32 or
/// binary64 limit. Equivalent decimal/exponent spellings have the same key.
pub struct JsonInteger {
  wire : Json
  canonical : String
} derive(Debug)

///|
pub fn JsonInteger::from_json(value : Json) -> JsonInteger raise MCPError {
  guard value is Number(number, repr~) else {
    raise InvalidRequest("Expected a JSON integer")
  }
  let literal = match repr {
    Some(literal) => literal
    None => {
      guard !number.is_nan() && !number.is_inf() else {
        raise InvalidRequest("Non-finite number has no JSON integer literal")
      }
      value.stringify()
    }
  }
  guard integer_key(literal) is Some(canonical) else {
    raise InvalidRequest("Expected a mathematical JSON integer")
  }
  if repr is Some(_) {
    let decoded = @json.parse(literal) catch {
      _ => raise InvalidRequest("Invalid JSON integer representation")
    }
    guard decoded is Number(expected, ..) &&
      !number.is_nan() &&
      expected == number else {
      raise InvalidRequest(
        "JSON integer representation contradicts its numeric value",
      )
    }
  }
  { wire: Json::number(number, repr=literal), canonical, }
}

///|
pub fn JsonInteger::from_literal(
  literal : String,
) -> JsonInteger raise MCPError {
  let parsed = @json.parse(literal) catch {
    _ => raise InvalidRequest("Invalid JSON integer literal")
  }
  guard parsed is Number(number, ..) else {
    raise InvalidRequest("Expected a JSON integer literal")
  }
  JsonInteger::from_json(Json::number(number, repr=literal))
}

///|
pub fn JsonInteger::from_int(value : Int) -> JsonInteger {
  let literal = value.to_string()
  {
    wire: Json::number(value.to_double(), repr=literal),
    canonical: integer_key(literal).unwrap(),
  }
}

///|
pub fn JsonInteger::to_json(self : JsonInteger) -> Json {
  self.wire
}

///|
pub fn JsonInteger::to_json_string(self : JsonInteger) -> String {
  self.wire.stringify()
}

///|
/// Returns None rather than narrowing an out-of-range integer.
pub fn JsonInteger::as_int(self : JsonInteger) -> Int? {
  guard self.wire is Number(value, ..) &&
    !value.is_nan() &&
    !value.is_inf() &&
    value >= -2147483648 &&
    value <= 2147483647 else {
    return None
  }
  let narrowed = value.to_int()
  if JsonInteger::from_int(narrowed).canonical == self.canonical {
    Some(narrowed)
  } else {
    None
  }
}

///|
/// Compact canonical identity; huge exponents do not allocate expanded zeros.
pub fn JsonInteger::key(self : JsonInteger) -> String {
  self.canonical
}

///|
pub impl Eq for JsonInteger with fn equal(self, other) {
  self.canonical == other.canonical
}

///|
fn integer_key(literal : String, integer_only? : Bool = true) -> String? {
  let length = literal.length()
  let negative = length > 0 && literal[0] == '-'
  let mut pos = if negative { 1 } else { 0 }
  let integer_start = pos
  if pos >= length {
    return None
  }
  if literal[pos] == '0' {
    pos += 1
  } else if literal[pos] is ('1'..='9') {
    while pos < length && literal[pos] is ('0'..='9') {
      pos += 1
    }
  } else {
    return None
  }
  let integer_end = pos
  let mut fraction_start = pos
  let mut fraction_end = pos
  if pos < length && literal[pos] == '.' {
    pos += 1
    fraction_start = pos
    while pos < length && literal[pos] is ('0'..='9') {
      pos += 1
    }
    fraction_end = pos
    if fraction_start == fraction_end {
      return None
    }
  }
  let mut exponent = @bigint.BigInt::from_int(0)
  if pos < length && literal[pos] is ('e' | 'E') {
    pos += 1
    let exponent_negative = pos < length && literal[pos] == '-'
    if pos < length && literal[pos] is ('+' | '-') {
      pos += 1
    }
    let exponent_start = pos
    while pos < length && literal[pos] is ('0'..='9') {
      pos += 1
    }
    if exponent_start == pos {
      return None
    }
    exponent = @bigint.BigInt::from_string(
      literal[exponent_start:pos].to_owned(),
    )
    if exponent_negative {
      exponent = -exponent
    }
  }
  if pos != length {
    return None
  }
  let digits = literal[integer_start:integer_end].to_owned() +
    literal[fraction_start:fraction_end].to_owned()
  let mut start = 0
  while start < digits.length() && digits[start] == '0' {
    start += 1
  }
  if start == digits.length() {
    return Some("0e0")
  }
  let mut end = digits.length()
  while end > start && digits[end - 1] == '0' {
    end -= 1
  }
  exponent = exponent +
    @bigint.BigInt::from_int(
      digits.length() - end - (fraction_end - fraction_start),
    )
  if integer_only && exponent < @bigint.BigInt::from_int(0) {
    return None
  }
  Some(
    (if negative { "-" } else { "" }) +
    digits[start:end].to_owned() +
    "e" +
    exponent.to_string(),
  )
}

///|
pub extend JsonInteger with Eq::{equal, not_equal}

///|
pub extend JsonInteger with @moonbitlang/core/debug.Debug::{to_repr}
