///|
/// Compile a schema once. Unknown extension keywords are annotations; known
/// malformed keywords fail compilation. References and unevaluated keywords
/// are explicitly refused until their evaluation semantics are implemented.
pub fn Schema::compile(
  document : Json,
  max_depth? : Int = 128,
) -> Schema raise CompileError {
  if max_depth < 1 {
    raise CompileError::DepthLimit(max_depth)
  }
  check_schema_json(document, "", 0, max_depth)
  { plan: compile_node(document, "", 0, max_depth), }
}

///|
// Bound annotation/const/enum traversal too, not just schema-node recursion.
fn check_schema_json(
  value : Json,
  path : String,
  depth : Int,
  limit : Int,
) -> Unit raise CompileError {
  if depth > limit {
    raise CompileError::DepthLimit(limit)
  }
  match value {
    Number(_, ..) =>
      if ExactNumber::of_json(value) is None {
        invalid_keyword(path, "invalid JSON number or numeric representation")
      }
    Object(fields) =>
      for name, child in fields {
        check_schema_json(child, pointer_step(path, name), depth + 1, limit)
      }
    Array(values) =>
      for index, child in values {
        check_schema_json(
          child,
          pointer_step(path, index.to_string()),
          depth + 1,
          limit,
        )
      }
    _ => ()
  }
}

///|
fn invalid_keyword(path : String, reason : String) -> Unit raise CompileError {
  raise InvalidKeyword(path~, reason~)
}

///|
fn compile_number(
  value : Json,
  path : String,
) -> ExactNumber raise CompileError {
  match ExactNumber::of_json(value) {
    Some(number) => number
    None => {
      invalid_keyword(path, "expected a finite JSON number")
      ExactNumber::from_double(0.0)
    }
  }
}

///|
fn compile_count(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int? raise CompileError {
  match fields.get(key) {
    None => None
    Some(value) => {
      let location = pointer_step(path, key)
      let number = compile_number(value, location)
      let integer = number.is_integer() catch {
        _ =>
          raise InvalidKeyword(
            path=location,
            reason="invalid numeric representation",
          )
      }
      let sign = number.sign() catch {
        _ =>
          raise InvalidKeyword(
            path=location,
            reason="invalid numeric representation",
          )
      }
      if !integer || sign < 0 {
        invalid_keyword(location, "expected a nonnegative integer")
      }
      let ordering = number.compare(ExactNumber::from_double(2147483647.0)) catch {
        _ =>
          raise InvalidKeyword(
            path=location,
            reason="invalid numeric representation",
          )
      }
      if ordering > 0 {
        raise UnsupportedKeyword(
          path=location,
          keyword="count exceeds supported range",
        )
      }
      match value {
        Number(d, ..) => Some(d.to_int())
        _ => None
      }
    }
  }
}

///|
fn compile_strings(
  value : Json,
  path : String,
) -> Array[String] raise CompileError {
  guard value is Array(values) else {
    invalid_keyword(path, "expected an array of unique strings")
    return []
  }
  let strings : Array[String] = []
  let seen : Set[String] = Set([])
  for item in values {
    guard item is String(text) else {
      invalid_keyword(path, "expected an array of unique strings")
      continue
    }
    if seen.contains(text) {
      invalid_keyword(path, "duplicate string")
    }
    seen.add(text)
    strings.push(text)
  }
  strings
}

///|
fn compile_type(value : Json, path : String) -> ValueType raise CompileError {
  match value {
    "null" => NullType
    "boolean" => BooleanType
    "number" => NumberType
    "integer" => IntegerType
    "string" => StringType
    "array" => ArrayType
    "object" => ObjectType
    _ => {
      invalid_keyword(path, "unknown JSON Schema type")
      NullType
    }
  }
}

///|
fn optional_node(
  fields : Map[String, Json],
  key : String,
  path : String,
  depth : Int,
  limit : Int,
) -> Plan? raise CompileError {
  fields
  .get(key)
  .map(value => compile_node(value, pointer_step(path, key), depth + 1, limit))
}

///|
fn compile_branches(
  value : Json,
  path : String,
  depth : Int,
  limit : Int,
) -> Array[Plan] raise CompileError {
  guard value is Array(branches) && !branches.is_empty() else {
    invalid_keyword(path, "expected a nonempty array of schemas")
    return []
  }
  branches.mapi((index, schema) => {
    compile_node(
      schema,
      pointer_step(path, index.to_string()),
      depth + 1,
      limit,
    )
  })
}

///|
fn compile_pattern_at(
  value : Json,
  path : String,
) -> PatternSupport raise CompileError {
  guard value is String(text) else {
    invalid_keyword(path, "expected a pattern string")
    return compile_pattern("")
  }
  let support = compile_pattern(text)
  match support {
    Unsupported(reason~) =>
      raise UnsupportedPattern(path~, pattern=text, reason~)
    Supported(_) => support
  }
}

///|
fn compile_node(
  document : Json,
  path : String,
  depth : Int,
  limit : Int,
) -> Plan raise CompileError {
  if depth > limit {
    raise CompileError::DepthLimit(limit)
  }
  match document {
    True => return Accept
    False => return Reject(path)
    Object(_) => ()
    _ => {
      invalid_keyword(path, "schema must be an object or boolean")
      return Accept
    }
  }
  guard document is Object(fields) else { return Accept }
  let rules : Array[Rule] = []
  for key, value in fields {
    let location = pointer_step(path, key)
    match key {
      "$schema" => {
        guard value is String(uri) else {
          invalid_keyword(location, "expected a dialect URI")
          continue
        }
        if uri != "https://json-schema.org/draft/2020-12/schema" {
          raise UnknownDialect(uri)
        }
      }
      "$ref"
      | "$dynamicRef"
      | "$id"
      | "$anchor"
      | "$dynamicAnchor"
      | "$vocabulary"
      | "unevaluatedProperties"
      | "unevaluatedItems" =>
        raise UnsupportedKeyword(path=location, keyword=key)
      "$defs" => {
        guard value is Object(definitions) else {
          invalid_keyword(location, "expected a map of schemas")
          continue
        }
        for name, schema in definitions {
          ignore(
            compile_node(schema, pointer_step(location, name), depth + 1, limit),
          )
        }
      }
      "type" => {
        let types = match value {
          Array(_) => {
            let names = compile_strings(value, location)
            if names.is_empty() {
              invalid_keyword(location, "type array must not be empty")
            }
            names.map(name => compile_type(Json::string(name), location))
          }
          _ => [compile_type(value, location)]
        }
        rules.push(Types(types, location))
      }
      "const" => rules.push(Constant(owned_json(value), location))
      "enum" => {
        guard value is Array(values) && !values.is_empty() else {
          invalid_keyword(location, "enum must be a nonempty array")
          continue
        }
        rules.push(Enumeration(values.map(owned_json), location))
      }
      "minimum" | "exclusiveMinimum" =>
        rules.push(
          Lower(
            compile_number(value, location),
            key == "exclusiveMinimum",
            location,
          ),
        )
      "maximum" | "exclusiveMaximum" =>
        rules.push(
          Upper(
            compile_number(value, location),
            key == "exclusiveMaximum",
            location,
          ),
        )
      "multipleOf" => {
        let divisor = compile_number(value, location)
        let sign = divisor.sign() catch {
          _ =>
            raise InvalidKeyword(
              path=location,
              reason="invalid numeric representation",
            )
        }
        if sign <= 0 {
          invalid_keyword(location, "multipleOf must be strictly positive")
        }
        rules.push(Multiple(divisor, location))
      }
      "pattern" =>
        rules.push(Pattern(compile_pattern_at(value, location), location))
      "allOf" =>
        rules.push(
          All(compile_branches(value, location, depth, limit), location),
        )
      "anyOf" =>
        rules.push(
          Any(compile_branches(value, location, depth, limit), location),
        )
      "oneOf" =>
        rules.push(
          One(compile_branches(value, location, depth, limit), location),
        )
      "not" =>
        rules.push(
          Negate(compile_node(value, location, depth + 1, limit), location),
        )
      "title"
      | "description"
      | "$comment"
      | "format"
      | "contentEncoding"
      | "contentMediaType" =>
        if !(value is String(_)) {
          invalid_keyword(location, "expected a string annotation")
        }
      "deprecated" | "readOnly" | "writeOnly" =>
        if value != Json::boolean(true) && value != Json::boolean(false) {
          invalid_keyword(location, "expected a boolean annotation")
        }
      "examples" =>
        if !(value is Array(_)) {
          invalid_keyword(location, "expected an array annotation")
        }
      "contentSchema" => ignore(compile_node(value, location, depth + 1, limit))
      _ => ()
    }
  }
  let min_length = compile_count(fields, "minLength", path)
  let max_length = compile_count(fields, "maxLength", path)
  if min_length is Some(_) || max_length is Some(_) {
    rules.push(StringLength(min_length, max_length, path))
  }
  // Compile conditional arms even when `if` is absent: their shapes must
  // still be legal, although their validation effects are then ignored.
  let condition = optional_node(fields, "if", path, depth, limit)
  let consequent = optional_node(fields, "then", path, depth, limit)
  let alternate = optional_node(fields, "else", path, depth, limit)
  if condition is Some(predicate) {
    rules.push(Conditional(predicate, consequent, alternate))
  }
  let properties : Map[String, Plan] = Map([])
  if fields.get("properties") is Some(value) {
    guard value is Object(schemas) else {
      invalid_keyword(
        pointer_step(path, "properties"),
        "expected a map of schemas",
      )
      return Accept
    }
    for name, schema in schemas {
      properties.set(
        name,
        compile_node(
          schema,
          pointer_step(pointer_step(path, "properties"), name),
          depth + 1,
          limit,
        ),
      )
    }
  }
  let patterns : Array[(PatternSupport, Plan)] = []
  if fields.get("patternProperties") is Some(value) {
    guard value is Object(schemas) else {
      invalid_keyword(
        pointer_step(path, "patternProperties"),
        "expected a map of schemas",
      )
      return Accept
    }
    for expression, schema in schemas {
      let location = pointer_step(
        pointer_step(path, "patternProperties"),
        expression,
      )
      patterns.push(
        (
          compile_pattern_at(Json::string(expression), location),
          compile_node(schema, location, depth + 1, limit),
        ),
      )
    }
  }
  let required = match fields.get("required") {
    Some(value) => compile_strings(value, pointer_step(path, "required"))
    None => []
  }
  let dependent_required : Array[(String, Array[String])] = []
  if fields.get("dependentRequired") is Some(value) {
    guard value is Object(dependencies) else {
      invalid_keyword(pointer_step(path, "dependentRequired"), "expected a map")
      return Accept
    }
    for name, names in dependencies {
      dependent_required.push(
        (
          name,
          compile_strings(
            names,
            pointer_step(pointer_step(path, "dependentRequired"), name),
          ),
        ),
      )
    }
  }
  let dependent_schemas : Array[(String, Plan)] = []
  if fields.get("dependentSchemas") is Some(value) {
    guard value is Object(dependencies) else {
      invalid_keyword(pointer_step(path, "dependentSchemas"), "expected a map")
      return Accept
    }
    for name, schema in dependencies {
      dependent_schemas.push(
        (
          name,
          compile_node(
            schema,
            pointer_step(pointer_step(path, "dependentSchemas"), name),
            depth + 1,
            limit,
          ),
        ),
      )
    }
  }
  let object_plan : ObjectPlan = {
    path,
    properties,
    patterns,
    required,
    dependent_required,
    dependent_schemas,
    additional: optional_node(
      fields, "additionalProperties", path, depth, limit,
    ),
    names: optional_node(fields, "propertyNames", path, depth, limit),
    minimum: compile_count(fields, "minProperties", path),
    maximum: compile_count(fields, "maxProperties", path),
  }
  if [
      "properties", "patternProperties", "required", "additionalProperties", "propertyNames",
      "minProperties", "maxProperties", "dependentRequired", "dependentSchemas",
    ].any(key => fields.contains(key)) {
    rules.push(Objects(object_plan))
  }
  let prefix = match fields.get("prefixItems") {
    None => []
    Some(value) =>
      compile_branches(value, pointer_step(path, "prefixItems"), depth, limit)
  }
  let unique = match fields.get("uniqueItems") {
    Some(True) => true
    None | Some(False) => false
    _ => {
      invalid_keyword(pointer_step(path, "uniqueItems"), "expected a boolean")
      false
    }
  }
  let array_plan : ArrayPlan = {
    path,
    prefix,
    unique,
    items: optional_node(fields, "items", path, depth, limit),
    contains: optional_node(fields, "contains", path, depth, limit),
    min_contains: compile_count(fields, "minContains", path).unwrap_or(1),
    max_contains: compile_count(fields, "maxContains", path),
    minimum: compile_count(fields, "minItems", path),
    maximum: compile_count(fields, "maxItems", path),
  }
  if [
      "prefixItems", "items", "contains", "minContains", "maxContains", "minItems",
      "maxItems", "uniqueItems",
    ].any(key => fields.contains(key)) {
    rules.push(Arrays(array_plan))
  }
  Rules(rules)
}
