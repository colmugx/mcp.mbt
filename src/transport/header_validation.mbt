///|
/// Decode a mirrored value exactly once; malformed sentinels are not plain text.
fn decode_mirrored_header(value : String) -> Result[String, String] {
  if looks_like_sentinel(value) {
    match decode_base64_sentinel(value) {
      Some(decoded) => Ok(decoded)
      None => Err("Malformed Base64 header value")
    }
  } else if is_header_safe(value) {
    Ok(value)
  } else {
    Err("Header value requires Base64 encoding")
  }
}

///|
fn argument_at_path(arguments : Json, path : Array[String]) -> Json? {
  for key in path; current = Some(arguments) {
    continue match current {
        Some(Object(fields)) => fields.get(key)
        _ => None
      }
  } nobreak {
    current
  }
}

///|
fn header_matches_argument(decoded : String, value : Json) -> Bool {
  match value {
    String(expected) => decoded == expected
    True => decoded == "true"
    False => decoded == "false"
    Number(_, ..) => {
      if !@validation.is_safe_integer(value) {
        return false
      }
      let actual = @validation.parse_json(decoded) catch { _ => return false }
      @validation.is_safe_integer(actual) &&
      @validation.json_equal(actual, value)
    }
    _ => false
  }
}

///|
/// Validate recognized x-mcp-header values against their exact argument paths.
/// Unrecognized Mcp-Param headers are ignored, not treated as body parameters.
pub fn validate_tool_parameter_headers(
  input_schema : Json,
  arguments : Json,
  headers : Array[(String, String)],
) -> Result[Unit, String] {
  let bindings = match validate_tool_header_schema(input_schema) {
    Valid(bindings) => bindings
    Invalid(reason) => return Err("Invalid tool header schema: " + reason)
  }
  let supplied : Map[String, Array[String]] = Map([])
  for (name, value) in headers {
    let name = name.to_lower()
    match supplied.get(name) {
      Some(values) => values.push(value)
      None => supplied.set(name, [value])
    }
  }
  for (path, suffix) in bindings {
    let name = "mcp-param-" + suffix.to_lower()
    let value = argument_at_path(arguments, path)
    let header = supplied.get(name)
    match (value, header) {
      (None, None) | (Some(Null), None) => ()
      (None, Some(_)) | (Some(Null), Some(_)) =>
        return Err(
          "Unexpected " + name + " header for an absent or null argument",
        )
      (Some(_), None) => return Err("Missing required " + name + " header")
      (Some(value), Some(values)) => {
        if values.length() != 1 {
          return Err("Duplicate " + name + " header")
        }
        let decoded = match decode_mirrored_header(values[0]) {
          Ok(value) => value
          Err(reason) => return Err(name + ": " + reason)
        }
        if !header_matches_argument(decoded, value) {
          return Err(name + " header does not match body argument")
        }
      }
    }
  }
  Ok(())
}
