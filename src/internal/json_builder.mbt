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
  "\"" + escape_json_string(s) + "\""
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
    let mut result = "{"
    let mut first = true
    for pair in pairs {
      if not(first) {
        result = result + ","
      }
      first = false
      let (key, value) = pair
      result = result + "\"" + key + "\":" + value
    }
    result + "}"
  }
}

///|
/// Build JSON array from values
pub fn json_array(values : Array[String]) -> String {
  if values.is_empty() {
    "[]"
  } else {
    let mut result = "["
    let mut first = true
    for value in values {
      if not(first) {
        result = result + ","
      }
      first = false
      result = result + value
    }
    result + "]"
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
