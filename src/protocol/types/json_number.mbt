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
/// Lossless for the Double itself: the shortest round-trip literal is kept,
/// so programmatic doubles serialize exactly. Digits already lost to binary64
/// cannot be recovered; non-finite doubles have no JSON literal.
pub fn JsonNumber::from_double(value : Double) -> JsonNumber raise MCPError {
  JsonNumber::from_json(Json::number(value))
}

///|
pub fn JsonNumber::to_json(self : JsonNumber) -> Json {
  self.wire
}

///|
/// Explicitly lossy Double view for display or limit checks; the wire
/// identity and equality stay exact.
pub fn JsonNumber::as_double(self : JsonNumber) -> Double {
  match self.wire {
    Number(value, ..) => value
    _ => abort("JsonNumber always carries a JSON number")
  }
}

///|
pub fn JsonNumber::key(self : JsonNumber) -> String {
  self.canonical
}

///|
/// Exact mathematical ordering, including fractional spellings. Comparison
/// uses canonical identities, never rounded doubles, and does not expand
/// huge exponents.
pub fn JsonNumber::compare(self : JsonNumber, other : JsonNumber) -> Int32 {
  decimal_key_compare(self.canonical, other.canonical)
}

///|
/// Canonical key layout is `[sign]digits e exponent` without leading or
/// trailing zeros, so ordering needs only digit and exponent comparisons and
/// never expands huge exponents. `"0e0"` is the single zero spelling.
fn decimal_key_compare(left : String, right : String) -> Int32 {
  let left_zero = left == "0e0"
  let right_zero = right == "0e0"
  match (left_zero, right_zero) {
    (true, true) => 0
    (true, false) => if right[0] == '-' { 1 } else { -1 }
    (false, true) => if left[0] == '-' { -1 } else { 1 }
    (false, false) => {
      let (left_negative, left_digits, left_exponent) = decimal_key_parts(left)
      let (right_negative, right_digits, right_exponent) = decimal_key_parts(
        right,
      )
      if left_negative != right_negative {
        return if left_negative { -1 } else { 1 }
      }
      let magnitude = decimal_magnitude_compare(
        left_digits, left_exponent, right_digits, right_exponent,
      )
      if left_negative {
        -magnitude
      } else {
        magnitude
      }
    }
  }
}

///|
fn decimal_key_parts(key : String) -> (Bool, String, @bigint.BigInt) {
  let negative = key[0] == '-'
  let mut end = if negative { 1 } else { 0 }
  while key[end] != 'e' {
    end += 1
  }
  let digits = key[if negative { 1 } else { 0 }:end].to_owned()
  let exponent = @bigint.BigInt::from_string(key[end + 1:].to_owned())
  (negative, digits, exponent)
}

///|
fn decimal_magnitude_compare(
  left_digits : String,
  left_exponent : @bigint.BigInt,
  right_digits : String,
  right_exponent : @bigint.BigInt,
) -> Int32 {
  let left_shift = left_exponent +
    @bigint.BigInt::from_int(left_digits.length() - 1)
  let right_shift = right_exponent +
    @bigint.BigInt::from_int(right_digits.length() - 1)
  if left_shift != right_shift {
    return if left_shift < right_shift { -1 } else { 1 }
  }
  let shared = if left_digits.length() < right_digits.length() {
    left_digits.length()
  } else {
    right_digits.length()
  }
  for index in 0..<shared {
    if left_digits[index] != right_digits[index] {
      return if left_digits[index] < right_digits[index] { -1 } else { 1 }
    }
  }
  // Canonical digits never end in zero, so the longer side carries extra value.
  left_digits.length() - right_digits.length()
}

///|
pub impl Eq for JsonNumber with fn equal(self, other) {
  self.canonical == other.canonical
}

///|
pub extend JsonNumber with Eq::{equal, not_equal}

///|
pub extend JsonNumber with @moonbitlang/core/debug.Debug::{to_repr}
