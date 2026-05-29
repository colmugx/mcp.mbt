///|
pub fn extract_string_from_json(json : Json, field : String) -> String? {
  if json is Object(obj) {
    match obj.get(field) {
      Some(String(s)) => Some(s)
      _ => None
    }
  } else {
    None
  }
}

///|
pub fn extract_int_from_json(json : Json, field : String) -> Int? {
  if json is Object(obj) {
    match obj.get(field) {
      Some(Number(n, ..)) => Some(n.to_int())
      _ => None
    }
  } else {
    None
  }
}
