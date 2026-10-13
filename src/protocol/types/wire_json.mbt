///|
fn wire_object(value : Json) -> Map[String, Json] raise MCPError {
  match value {
    Object(fields) => fields
    _ => raise InvalidParams("Expected a JSON object")
  }
}

///|
fn wire_string(
  fields : Map[String, Json],
  key : String,
) -> String raise MCPError {
  match fields.get(key) {
    Some(String(value)) => value
    _ => raise InvalidParams("Missing or invalid '\{key}' string field")
  }
}

///|
fn wire_optional_string(
  fields : Map[String, Json],
  key : String,
) -> String? raise MCPError {
  match fields.get(key) {
    None => None
    Some(String(value)) => Some(value)
    _ => raise InvalidParams("Invalid '\{key}' string field")
  }
}

///|
fn wire_optional_bool(
  fields : Map[String, Json],
  key : String,
) -> Bool? raise MCPError {
  match fields.get(key) {
    None => None
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => raise InvalidParams("Invalid '\{key}' boolean field")
  }
}

///|
fn wire_put_bool(
  fields : Map[String, Json],
  key : String,
  value : Bool?,
) -> Unit {
  match value {
    Some(value) => fields.set(key, Json::boolean(value))
    None => ()
  }
}

///|
fn wire_optional_object(
  fields : Map[String, Json],
  key : String,
) -> Map[String, Json]? raise MCPError {
  match fields.get(key) {
    None => None
    Some(Object(value)) => Some(value.copy())
    _ => raise InvalidParams("Invalid '\{key}' object field")
  }
}

///|
fn wire_optional_strings(
  fields : Map[String, Json],
  key : String,
) -> Array[String]? raise MCPError {
  match fields.get(key) {
    None => None
    Some(Array(values)) =>
      Some(
        values.map(value => {
          match value {
            String(text) => text
            _ => raise InvalidParams("Invalid '\{key}' string array")
          }
        }),
      )
    _ => raise InvalidParams("Invalid '\{key}' array field")
  }
}

///|
fn wire_extensions(
  fields : Map[String, Json],
  owned : Array[String],
) -> Map[String, Json] {
  let extensions = fields.copy()
  for key in owned {
    extensions.remove(key)
  }
  extensions
}

///|
fn wire_put_string(
  fields : Map[String, Json],
  key : String,
  value : String?,
) -> Unit {
  match value {
    Some(value) => fields.set(key, Json::string(value))
    None => ()
  }
}

///|
fn wire_put_meta(fields : Map[String, Json], meta : Map[String, Json]?) -> Unit {
  match meta {
    Some(meta) => fields.set("_meta", Json::object(meta.copy()))
    None => ()
  }
}

///|
/// Exact integer decode: the wire literal decides integrality, so fractional
/// or contradicting representations fail instead of passing a rounded check.
fn wire_integer(
  fields : Map[String, Json],
  key : String,
) -> JsonInteger raise MCPError {
  match fields.get(key) {
    Some(value) =>
      JsonInteger::from_json(value) catch {
        _ => raise InvalidParams("Missing or invalid '\{key}' integer")
      }
    None => raise InvalidParams("Missing or invalid '\{key}' integer")
  }
}

///|
/// Exact number decode: literal spellings are retained and non-finite
/// constructs are rejected rather than narrowed.
fn wire_exact_number(
  fields : Map[String, Json],
  key : String,
) -> JsonNumber raise MCPError {
  match fields.get(key) {
    Some(value) =>
      JsonNumber::from_json(value) catch {
        _ => raise InvalidParams("Missing or invalid '\{key}' finite number")
      }
    None => raise InvalidParams("Missing or invalid '\{key}' finite number")
  }
}

///|
fn wire_optional_exact_number(
  fields : Map[String, Json],
  key : String,
) -> JsonNumber? raise MCPError {
  if fields.contains(key) {
    Some(wire_exact_number(fields, key))
  } else {
    None
  }
}

///|
fn wire_put_exact_number(
  fields : Map[String, Json],
  key : String,
  value : JsonNumber?,
) -> Unit {
  match value {
    Some(value) => fields.set(key, value.to_json())
    None => ()
  }
}

///|
/// Exact unit-interval membership on canonical keys; fractional boundary
/// spellings such as `1.00000000000000000001` or `-1e-400` stay outside.
fn exact_unit_range(key : String) -> Bool {
  decimal_key_compare(key, "0e0") >= 0 && decimal_key_compare(key, "1e0") <= 0
}
