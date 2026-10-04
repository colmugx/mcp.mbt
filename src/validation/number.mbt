///|
/// Safe-integer headers require mathematical integrality, not just a rounded
/// Double that happens to be integral (e.g. 42.0000000000000000000001).
pub fn is_safe_integer(value : Json) -> Bool {
  guard value is Number(number, ..) &&
    !number.is_nan() &&
    !number.is_inf() &&
    number >= -9007199254740991 &&
    number <= 9007199254740991 else {
    return false
  }
  match @schema.ExactNumber::of_json(value) {
    Some(number) => number.is_integer() catch { _ => false }
    None => false
  }
}
