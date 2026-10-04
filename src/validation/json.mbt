///|
/// Preserve decimal literals at wire boundaries and when constructing schemas.
/// Core JSON can preserve large integers while still rounding long decimals.
pub fn parse_json(source : StringView) -> Json raise @types.MCPError {
  @schema.parse(source, max_nesting_depth=1024) catch {
    error => raise @types.ParseError("Invalid JSON: \{Repr(error)}")
  }
}

///|
/// Mathematical JSON equality for metadata headers, without binary64 aliasing.
pub fn json_equal(left : Json, right : Json) -> Bool {
  match (left, right) {
    (Number(_, ..), Number(_, ..)) =>
      match
        (
          @schema.ExactNumber::of_json(left),
          @schema.ExactNumber::of_json(right),
        ) {
        (Some(a), Some(b)) => a.equal(b) catch { _ => false }
        _ => false
      }
    (Object(a), Object(b)) => {
      if a.length() != b.length() {
        return false
      }
      for key, value in a {
        guard b.get(key) is Some(other) && json_equal(value, other) else {
          return false
        }
      }
      true
    }
    (Array(a), Array(b)) => {
      if a.length() != b.length() {
        return false
      }
      for index, value in a {
        if !json_equal(value, b[index]) {
          return false
        }
      }
      true
    }
    _ => left == right
  }
}

///|
/// Freeze the advertised definition alongside its compiled validators.
pub fn owned_json(value : Json) -> Json raise @types.MCPError {
  copy_json(value, 0)
}

///|
fn copy_json(value : Json, depth : Int) -> Json raise @types.MCPError {
  if depth > 128 {
    raise @types.InvalidParams(
      "Tool definition exceeds the supported nesting depth",
    )
  }
  match value {
    Object(fields) => {
      let copy : Map[String, Json] = Map([])
      for key, child in fields {
        copy[key] = copy_json(child, depth + 1)
      }
      Json::object(copy)
    }
    Array(values) =>
      Json::array(values.map(value => copy_json(value, depth + 1)))
    _ => value
  }
}
