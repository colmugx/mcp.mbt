///|
fn escape_json_string(s : String) -> String {
  let builder = StringBuilder::new()
  let len = s.length()
  let mut i = 0
  while i < len {
    let ch = s[i].unsafe_to_char()
    match ch {
      '\\' => builder.write_string("\\\\")
      '"' => builder.write_string("\\\"")
      '\n' => builder.write_string("\\n")
      '\r' => builder.write_string("\\r")
      '\t' => builder.write_string("\\t")
      _ => builder.write_char(ch)
    }
    i = i + 1
  }
  builder.to_string()
}

///|
pub fn json_string(s : String) -> String {
  let builder = StringBuilder::new()
  builder.write_string("\"")
  builder.write_string(escape_json_string(s))
  builder.write_string("\"")
  builder.to_string()
}

///|
pub fn json_number(n : Int) -> String {
  n.to_string()
}

///|
pub fn json_bool(b : Bool) -> String {
  if b {
    "true"
  } else {
    "false"
  }
}

///|
pub fn json_object(pairs : Array[(String, String)]) -> String {
  if pairs.is_empty() {
    "{}"
  } else {
    let builder = StringBuilder::new()
    builder.write_string("{")
    let mut first = true
    for pair in pairs {
      if not(first) {
        builder.write_string(",")
      }
      first = false
      let (key, value) = pair
      builder.write_string("\"")
      builder.write_string(key)
      builder.write_string("\":")
      builder.write_string(value)
    }
    builder.write_string("}")
    builder.to_string()
  }
}

///|
/// Build JSON array from values
pub fn json_array(values : Array[String]) -> String {
  if values.is_empty() {
    "[]"
  } else {
    let builder = StringBuilder::new()
    builder.write_string("[")
    let mut first = true
    for value in values {
      if not(first) {
        builder.write_string(",")
      }
      first = false
      builder.write_string(value)
    }
    builder.write_string("]")
    builder.to_string()
  }
}

///|
pub fn jsonrpc_success(id : Int, result : String) -> String {
  json_object([
    ("jsonrpc", json_string("2.0")),
    ("id", json_number(id)),
    ("result", result),
  ])
}

///|
pub fn jsonrpc_error(id : Int, code : Int, message : String) -> String {
  let error_obj = json_object([
    ("code", json_number(code)),
    ("message", json_string(message)),
  ])
  json_object([
    ("jsonrpc", json_string("2.0")),
    ("id", json_number(id)),
    ("error", error_obj),
  ])
}

///|
pub fn jsonrpc_notification(method_name : String, params : Json?) -> String {
  match params {
    None =>
      json_object([
        ("jsonrpc", json_string("2.0")),
        ("method", json_string(method_name)),
      ])
    Some(p) => {
      let params_json = json_to_string(p)
      json_object([
        ("jsonrpc", json_string("2.0")),
        ("method", json_string(method_name)),
        ("params", params_json),
      ])
    }
  }
}

///|
/// Helper function to convert Json to string
fn json_to_string(json : Json) -> String {
  match json {
    String(s) => json_string(s)
    Number(n, ..) => n.to_string()
    True => json_bool(true)
    False => json_bool(false)
    Null => "null"
    Object(_) => json_object([])
    Array(_) => "[]"
  }
}
