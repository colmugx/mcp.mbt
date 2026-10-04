///|
/// Result of validating one tool's `x-mcp-header` mirror schema.
pub(all) enum HeaderSchemaValidation {
  Valid(Array[(Array[String], String)])
  Invalid(String)
}

///|
/// Validate a tool's `inputSchema` for `x-mcp-header` mirror annotations.
/// Returns the list of `(property_path, header_name)` entries when valid, or
/// an error message describing the first violation. Per the 2026-07-28
/// streamable HTTP spec:
///
/// * header names must be non-empty HTTP `tchar`s (RFC 9110 §5.1);
/// * names are case-insensitively unique within the tool;
/// * only `integer`, `string`, and `boolean` typed properties may carry the
///   annotation (not `number`);
/// * the annotation may only appear on properties statically reachable through
///   `properties` chains; any occurrence under `items`/`oneOf`/`anyOf`/`allOf`/
///   `if`/`then`/`else`/`$ref` invalidates the whole tool.
pub fn validate_tool_header_schema(
  input_schema : Json,
) -> HeaderSchemaValidation {
  validate_header_schema_node(input_schema, path=[], in_properties=false)
}

///|
fn validate_header_schema_node(
  schema : Json,
  path~ : Array[String],
  in_properties~ : Bool,
) -> HeaderSchemaValidation {
  match schema {
    Object(obj) => {
      // If we are in a property context and the property itself carries the
      // annotation, validate it before descending. The validated annotation
      // becomes this node's own entry in the collected result.
      let own_entries : Array[(Array[String], String)] = []
      if in_properties {
        match obj.get("x-mcp-header") {
          Some(String(header_name)) => {
            if header_name.length() == 0 {
              return Invalid("x-mcp-header value must be non-empty")
            }
            if !is_http_token(header_name) {
              return Invalid(
                "x-mcp-header contains invalid token characters: " + header_name,
              )
            }
            match property_type_is_primitive(obj) {
              false =>
                return Invalid(
                  "x-mcp-header can only annotate integer/string/boolean properties: " +
                  path.join("."),
                )
              true => ()
            }
            own_entries.push((path, header_name))
          }
          Some(_) =>
            return Invalid(
              "x-mcp-header value must be a string: " + path.join("."),
            )
          None => ()
        }
      } else if obj.contains("x-mcp-header") {
        // Annotation outside a property (root, items, combiners, etc.).
        return Invalid(
          "x-mcp-header must appear on a property: " + path.join("."),
        )
      }

      // Collect validated annotations and detect disallowed nesting.
      let collected : Array[(Array[String], String)] = []
      let disallowed = [
        "items", "oneOf", "anyOf", "allOf", "if", "then", "else", "$ref",
      ]
      for key, value in obj {
        if key == "properties" {
          match value {
            Object(props) =>
              for prop_name, prop_schema in props {
                let child_path = path.copy()
                child_path.push(prop_name)
                match
                  validate_header_schema_node(
                    prop_schema,
                    path=child_path,
                    in_properties=true,
                  ) {
                  Valid(entries) => collected.append(entries)
                  Invalid(msg) => return Invalid(msg)
                }
              }
            _ => ()
          }
        } else if disallowed.contains(key) {
          match validate_header_schema_node(value, path~, in_properties=false) {
            Valid(entries) =>
              if entries.length() > 0 {
                return Invalid(
                  "x-mcp-header cannot appear under '" +
                  key +
                  "' (must be via properties): " +
                  entries[0].0.join("."),
                )
              }
            Invalid(msg) => return Invalid(msg)
          }
        } else if key != "x-mcp-header" {
          // Other keys are allowed, but any annotation nested inside them is
          // not reachable through a pure `properties` chain.
          match validate_header_schema_node(value, path~, in_properties=false) {
            Valid(entries) =>
              if entries.length() > 0 {
                return Invalid(
                  "x-mcp-header must be reachable through properties: " +
                  entries[0].0.join("."),
                )
              }
            Invalid(msg) => return Invalid(msg)
          }
        }
      }

      // Enforce case-insensitive uniqueness among annotations found in this
      // tool's schema. Own annotation (if any) participates too.
      own_entries.append(collected)
      let seen : Map[String, Unit] = Default::default()
      for entry in own_entries {
        let lower = entry.1.to_lower()
        if seen.contains(lower) {
          return Invalid(
            "duplicate x-mcp-header (case-insensitive): " + entry.1,
          )
        }
        seen.set(lower, ())
      }
      Valid(own_entries)
    }
    Array(arr) => {
      let collected : Array[(Array[String], String)] = []
      for item in arr {
        match validate_header_schema_node(item, path~, in_properties=false) {
          Valid(entries) =>
            if entries.length() > 0 {
              return Invalid(
                "x-mcp-header cannot appear inside an array schema at path: " +
                path.join("."),
              )
            }
          Invalid(msg) => return Invalid(msg)
        }
      }
      Valid(collected)
    }
    _ => Valid([])
  }
}

///|
fn property_type_is_primitive(obj : Map[String, Json]) -> Bool {
  match obj.get("type") {
    Some(String("integer")) => true
    Some(String("string")) => true
    Some(String("boolean")) => true
    _ => false
  }
}

///|
/// Check whether every character is an HTTP `tchar` per RFC 9110 §5.1.
fn is_http_token(s : String) -> Bool {
  let mut ok = true
  for c in s {
    if !is_http_tchar(c) {
      ok = false
      break
    }
  }
  ok
}

///|
fn is_http_tchar(c : Char) -> Bool {
  if c >= 'A' && c <= 'Z' {
    return true
  }
  if c >= 'a' && c <= 'z' {
    return true
  }
  if c >= '0' && c <= '9' {
    return true
  }
  let token_specials = "!#$%&'*+-.^_`|~"
  for s in token_specials {
    if c == s {
      return true
    }
  }
  false
}
