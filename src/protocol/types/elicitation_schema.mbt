///|
/// Check the restricted wire union, not arbitrary JSON Schema keywords.
/// Unknown fields remain available for extensions; runtime compilation decides
/// whether any additional validation keywords can actually be enforced.
fn check_elicitation_schema(value : Json) -> Unit raise MCPError {
  let fields = wire_object(value)
  guard fields.get("type") is Some(String("object")) else {
    raise InvalidParams("Elicitation requestedSchema.type must be object")
  }
  ignore(wire_optional_string(fields, "$schema"))
  ignore(wire_optional_strings(fields, "required"))
  guard fields.get("properties") is Some(Object(properties)) else {
    raise InvalidParams("Elicitation requestedSchema requires properties")
  }
  for _, property in properties {
    check_elicitation_property(property)
  }
}

///|
fn check_elicitation_property(value : Json) -> Unit raise MCPError {
  let fields = wire_object(value)
  ignore(wire_optional_string(fields, "title"))
  ignore(wire_optional_string(fields, "description"))
  match wire_string(fields, "type") {
    "string" => {
      ignore(wire_optional_string(fields, "default"))
      ignore(wire_optional_number(fields, "minLength"))
      ignore(wire_optional_number(fields, "maxLength"))
      match wire_optional_string(fields, "format") {
        None | Some("email" | "uri" | "date" | "date-time") => ()
        Some(_) => raise InvalidParams("Invalid elicitation string format")
      }
      ignore(wire_optional_strings(fields, "enum"))
      ignore(wire_optional_strings(fields, "enumNames"))
      if fields.contains("oneOf") {
        check_elicitation_options(fields, "oneOf")
      }
    }
    "number" | "integer" => {
      ignore(wire_optional_number(fields, "minimum"))
      ignore(wire_optional_number(fields, "maximum"))
      ignore(wire_optional_number(fields, "default"))
    }
    "boolean" => ignore(wire_optional_bool(fields, "default"))
    "array" => {
      ignore(wire_optional_number(fields, "minItems"))
      ignore(wire_optional_number(fields, "maxItems"))
      ignore(wire_optional_strings(fields, "default"))
      guard fields.get("items") is Some(Object(items)) else {
        raise InvalidParams("Elicitation multi-select requires items")
      }
      if items.contains("anyOf") {
        check_elicitation_options(items, "anyOf")
      } else {
        guard items.get("type") is Some(String("string")) &&
          wire_optional_strings(items, "enum") is Some(_) else {
          raise InvalidParams(
            "Elicitation multi-select requires string enum items",
          )
        }
      }
    }
    _ =>
      raise InvalidParams(
        "Elicitation properties must be primitive or multi-select enums",
      )
  }
}

///|
fn check_elicitation_options(
  fields : Map[String, Json],
  keyword : String,
) -> Unit raise MCPError {
  guard fields.get(keyword) is Some(Array(options)) else {
    raise InvalidParams("Elicitation '" + keyword + "' must be an array")
  }
  for option in options {
    let fields = wire_object(option)
    ignore(wire_string(fields, "const"))
    ignore(wire_string(fields, "title"))
  }
}
