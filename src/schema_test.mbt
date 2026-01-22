///| =====================================================
///| Schema DSL Unit Tests
///| Tests for parameter definitions and schema generation
///| =====================================================

///| =====================================================
///| ParamDef Constructor Tests
///| =====================================================

test "string_param creates required string parameter" {
  let param = string_param("name", "User name")
  assert_eq(param.name, "name")
  assert_eq(param.description, "User name")
  assert_eq(param.type_, "string")
  assert_eq(param.required, true)
}

test "optional_string_param creates optional string parameter" {
  let param = optional_string_param("nickname", "Optional nickname")
  assert_eq(param.name, "nickname")
  assert_eq(param.description, "Optional nickname")
  assert_eq(param.type_, "string")
  assert_eq(param.required, false)
}

test "number_param creates required number parameter" {
  let param = number_param("count", "Item count")
  assert_eq(param.name, "count")
  assert_eq(param.description, "Item count")
  assert_eq(param.type_, "number")
  assert_eq(param.required, true)
}

test "optional_number_param creates optional number parameter" {
  let param = optional_number_param("limit", "Result limit")
  assert_eq(param.name, "limit")
  assert_eq(param.description, "Result limit")
  assert_eq(param.type_, "number")
  assert_eq(param.required, false)
}

test "boolean_param creates required boolean parameter" {
  let param = boolean_param("active", "Is active")
  assert_eq(param.name, "active")
  assert_eq(param.description, "Is active")
  assert_eq(param.type_, "boolean")
  assert_eq(param.required, true)
}

test "optional_boolean_param creates optional boolean parameter" {
  let param = optional_boolean_param("verbose", "Verbose output")
  assert_eq(param.name, "verbose")
  assert_eq(param.description, "Verbose output")
  assert_eq(param.type_, "boolean")
  assert_eq(param.required, false)
}

test "ParamDef derive Eq and Show" {
  let param1 = string_param("test", "Test parameter")
  let param2 = string_param("test", "Test parameter")
  let param3 = string_param("other", "Other parameter")

  // Test Eq
  assert_eq(param1, param2)
  assert_true(param1 != param3)

  // Test Show
  let str = param1.to_string()
  assert_true(str.contains("test"))
}

///| =====================================================
///| Schema Generation Tests
///| =====================================================

test "expand_params_to_json with empty params" {
  let params: Array[ParamDef] = []
  let schema = expand_params_to_json(params)

  // Should be an object with empty properties and required arrays
  match schema {
    Object(map) => {
      assert_eq(map.get("type"), Some(Json::string("object")))
      match map.get("properties") {
        Some(Object(props)) => assert_eq(props.length(), 0)
        _ => panic()
      }
      match map.get("required") {
        Some(Array(req)) => assert_eq(req.length(), 0)
        _ => panic()
      }
    }
    _ => panic()
  }
}

test "expand_params_to_json with single required string param" {
  let params = [string_param("name", "User name")]
  let schema = expand_params_to_json(params)

  match schema {
    Object(map) => {
      // Check type
      assert_eq(map.get("type"), Some(Json::string("object")))

      // Check properties
      match map.get("properties") {
        Some(Object(props)) => {
          assert_eq(props.length(), 1)
          match props.get("name") {
            Some(Object(prop)) => {
              assert_eq(prop.get("type"), Some(Json::string("string")))
              assert_eq(prop.get("description"), Some(Json::string("User name")))
            }
            _ => panic()
          }
        }
        _ => panic()
      }

      // Check required array
      match map.get("required") {
        Some(Array(req)) => {
          assert_eq(req.length(), 1)
          assert_eq(req[0], Json::string("name"))
        }
        _ => panic()
      }
    }
    _ => panic()
  }
}

test "expand_params_to_json with optional parameter" {
  let params = [
    string_param("required_field", "Required field"),
    optional_string_param("optional_field", "Optional field"),
  ]
  let schema = expand_params_to_json(params)

  match schema {
    Object(map) => {
      match map.get("properties") {
        Some(Object(props)) => {
          assert_eq(props.length(), 2)
        }
        _ => panic()
      }

      // Only required_field should be in required array
      match map.get("required") {
        Some(Array(req)) => {
          assert_eq(req.length(), 1)
          assert_eq(req[0], Json::string("required_field"))
        }
        _ => panic()
      }
    }
    _ => panic()
  }
}

test "expand_params_to_json with multiple parameter types" {
  let params = [
    string_param("text", "Text content"),
    number_param("count", "Item count"),
    boolean_param("enabled", "Is enabled"),
    optional_string_param("optional", "Optional parameter"),
  ]
  let schema = expand_params_to_json(params)

  match schema {
    Object(map) => {
      match map.get("properties") {
        Some(Object(props)) => {
          // Check all parameter types
          match props.get("text") {
            Some(Object(prop)) => {
              assert_eq(prop.get("type"), Some(Json::string("string")))
            }
            _ => panic()
          }

          match props.get("count") {
            Some(Object(prop)) => {
              assert_eq(prop.get("type"), Some(Json::string("number")))
            }
            _ => panic()
          }

          match props.get("enabled") {
            Some(Object(prop)) => {
              assert_eq(prop.get("type"), Some(Json::string("boolean")))
            }
            _ => panic()
          }

          match props.get("optional") {
            Some(Object(prop)) => {
              assert_eq(prop.get("type"), Some(Json::string("string")))
            }
            _ => panic()
          }
        }
        _ => panic()
      }

      // Check required array (should have 3 items, not optional)
      match map.get("required") {
        Some(Array(req)) => {
          assert_eq(req.length(), 3)
        }
        _ => panic()
      }
    }
    _ => panic()
  }
}

test "expand_params_to_json with parameter description" {
  let params = [string_param("query", "Search query string")]
  let schema = expand_params_to_json(params)

  match schema {
    Object(map) => {
      match map.get("properties") {
        Some(Object(props)) => {
          match props.get("query") {
            Some(Object(prop)) => {
              assert_eq(prop.get("description"), Some(Json::string("Search query string")))
              assert_eq(prop.get("type"), Some(Json::string("string")))
            }
            _ => panic()
          }
        }
        _ => panic()
      }
    }
    _ => panic()
  }
}

test "expand_params_to_json preserves parameter order" {
  let params = [
    string_param("first", "First parameter"),
    string_param("second", "Second parameter"),
    string_param("third", "Third parameter"),
  ]
  let schema = expand_params_to_json(params)

  match schema {
    Object(map) => {
      match map.get("required") {
        Some(Array(req)) => {
          assert_eq(req.length(), 3)
          assert_eq(req[0], Json::string("first"))
          assert_eq(req[1], Json::string("second"))
          assert_eq(req[2], Json::string("third"))
        }
        _ => panic()
      }
    }
    _ => panic()
  }
}

///| =====================================================
///| Example: Complete Tool Schema
///| =====================================================

struct SearchTool {}

impl Tool for SearchTool with name(_self : SearchTool) -> String {
  "search"
}

impl Tool for SearchTool with description(_self : SearchTool) -> String {
  "Search for items"
}

impl Tool for SearchTool with params(_self : SearchTool) -> Array[ParamDef] {
  [
    string_param("query", "Search query"),
    optional_number_param("limit", "Maximum results"),
    optional_string_param("sort", "Sort order"),
  ]
}

impl Tool for SearchTool with execute(_self : SearchTool, args : Json) -> ToolResult {
  let query = match get_string(args, "query") {
    Ok(q) => q
    Err(e) => return e
  }

  // Extract optional parameters with defaults
  let limit = match args {
    Object(map) => match map.get("limit") {
      Some(Number(n, ..)) => n.to_int()
      Some(Null) => 10
      None => 10
      _ => 10
    }
    _ => 10
  }

  let sort = match get_optional_string(args, "sort") {
    Ok(Some(s)) => s
    _ => "relevance"
  }

  ToolResult::text("Search: \{query}, limit: \{limit}, sort: \{sort}")
}

///|
async test "example: search tool with complete schema" {
  let tool = SearchTool::{  }
  let params = tool.params()
  let schema = expand_params_to_json(params)

  // Verify schema structure
  match schema {
    Object(map) => {
      match map.get("properties") {
        Some(Object(props)) => {
          // Should have 3 parameters
          assert_eq(props.length(), 3)

          // Check query parameter (required)
          match props.get("query") {
            Some(Object(prop)) => {
              assert_eq(prop.get("type"), Some(Json::string("string")))
              assert_eq(
                prop.get("description"),
                Some(Json::string("Search query")),
              )
            }
            _ => panic()
          }

          // Check limit parameter (optional)
          match props.get("limit") {
            Some(Object(prop)) => {
              assert_eq(prop.get("type"), Some(Json::string("number")))
              assert_eq(
                prop.get("description"),
                Some(Json::string("Maximum results")),
              )
            }
            _ => panic()
          }

          // Check sort parameter (optional)
          match props.get("sort") {
            Some(Object(prop)) => {
              assert_eq(prop.get("type"), Some(Json::string("string")))
              assert_eq(
                prop.get("description"),
                Some(Json::string("Sort order")),
              )
            }
            _ => panic()
          }
        }
        _ => panic()
      }

      // Only query should be required
      match map.get("required") {
        Some(Array(req)) => {
          assert_eq(req.length(), 1)
          assert_eq(req[0], Json::string("query"))
        }
        _ => panic()
      }
    }
    _ => panic()
  }

  // Test tool execution
  let args = Json::object({
    "query": Json::string("MoonBit"),
    "limit": Json::number(20.0),
  })
  let result = tool.execute(args)
  assert_eq(result.is_error, false)
  match result.content[0] {
    Text(msg) => {
      assert_true(msg.contains("Search: MoonBit"))
      assert_true(msg.contains("limit: 20"))
    }
    _ => panic()
  }
}
