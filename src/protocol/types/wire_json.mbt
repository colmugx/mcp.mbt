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
