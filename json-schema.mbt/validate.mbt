///|
/// Validate without allocating a diagnostic array. Invalid JSON numbers and
/// exhausted traversal budgets are errors, not ordinary validation failures.
pub fn Schema::valid(
  self : Schema,
  value : Json,
  max_depth? : Int = 128,
) -> Bool raise {
  check_instance(value, "", 0, max_depth)
  evaluate(self.plan, value, "", None, 0, max_depth)
}

///|
/// Collect assertion failures. Paths are RFC 6901 JSON Pointers; failed
/// speculative anyOf/oneOf/not/if branches do not leak their diagnostics.
pub fn Schema::faults(
  self : Schema,
  value : Json,
  max_depth? : Int = 128,
) -> Array[Fault] raise {
  check_instance(value, "", 0, max_depth)
  let failures : Array[Fault] = []
  ignore(evaluate(self.plan, value, "", Some(failures), 0, max_depth))
  failures
}

///|
fn check_instance(
  value : Json,
  path : String,
  depth : Int,
  limit : Int,
) -> Unit raise EvaluationError {
  if limit < 1 || depth > limit {
    raise EvaluationError::DepthLimit(limit)
  }
  match value {
    Number(_, ..) =>
      if ExactNumber::of_json(value) is None {
        raise InvalidNumber(path~)
      }
    Object(fields) =>
      for name, child in fields {
        check_instance(child, pointer_step(path, name), depth + 1, limit)
      }
    Array(values) =>
      for index, child in values {
        check_instance(
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
fn numeric_value(
  value : Json,
  path : String,
) -> ExactNumber raise EvaluationError {
  match ExactNumber::of_json(value) {
    Some(number) => number
    None => raise InvalidNumber(path~)
  }
}

///|
// JSON Schema equality compares numbers mathematically, including nested ones.
// Inputs have already passed numeric/depth checks before this recursion.
fn schema_equal(left : Json, right : Json) -> Bool raise NumericError {
  match (left, right) {
    (Number(_, ..), Number(_, ..)) =>
      match (ExactNumber::of_json(left), ExactNumber::of_json(right)) {
        (Some(a), Some(b)) => a.equal(b)
        _ => false
      }
    (Object(a), Object(b)) => {
      if a.length() != b.length() {
        return false
      }
      for key, value in a {
        match b.get(key) {
          Some(other) => if !schema_equal(value, other) { return false }
          None => return false
        }
      }
      true
    }
    (Array(a), Array(b)) => {
      if a.length() != b.length() {
        return false
      }
      for index, value in a {
        if !schema_equal(value, b[index]) {
          return false
        }
      }
      true
    }
    _ => left == right
  }
}

///|
fn fail(
  failures : Array[Fault]?,
  instance_path : String,
  schema_path : String,
  keyword : String,
  message : String,
) -> Bool {
  if failures is Some(entries) {
    entries.push({ instance_path, schema_path, keyword, message, })
  }
  false
}

///|
fn matches_type(kind : ValueType, value : Json, path : String) -> Bool raise {
  match (kind, value) {
    (NullType, Null)
    | (BooleanType, True)
    | (BooleanType, False)
    | (NumberType, Number(_, ..))
    | (StringType, String(_))
    | (ArrayType, Array(_))
    | (ObjectType, Object(_)) => true
    (IntegerType, Number(_, ..)) => numeric_value(value, path).is_integer()
    _ => false
  }
}

///|
fn evaluate(
  plan : Plan,
  value : Json,
  path : String,
  failures : Array[Fault]?,
  depth : Int,
  limit : Int,
) -> Bool raise {
  if depth > limit {
    raise EvaluationError::DepthLimit(limit)
  }
  match plan {
    Accept => true
    Reject(location) =>
      fail(
        failures, path, location, "false", "boolean schema rejects every instance",
      )
    Rules(rules) => {
      let mut valid = true
      for rule in rules {
        if !evaluate_rule(rule, value, path, failures, depth, limit) {
          valid = false
          if failures is None {
            return false
          }
        }
      }
      valid
    }
  }
}

///|
fn evaluate_rule(
  rule : Rule,
  value : Json,
  path : String,
  failures : Array[Fault]?,
  depth : Int,
  limit : Int,
) -> Bool raise {
  match rule {
    Types(types, location) => {
      for kind in types {
        if matches_type(kind, value, path) {
          return true
        }
      }
      fail(
        failures, path, location, "type", "instance has none of the permitted types",
      )
    }
    Constant(expected, location) =>
      schema_equal(value, expected) ||
      fail(
        failures, path, location, "const", "instance differs from the constant",
      )
    Enumeration(values, location) =>
      values.any(expected => schema_equal(value, expected)) ||
      fail(
        failures, path, location, "enum", "instance is not an enumerated value",
      )
    Lower(bound, exclusive, location) => {
      guard value is Number(_, ..) else { return true }
      let ordering = numeric_value(value, path).compare(bound)
      (if exclusive { ordering > 0 } else { ordering >= 0 }) ||
      fail(
        failures,
        path,
        location,
        if exclusive {
          "exclusiveMinimum"
        } else {
          "minimum"
        },
        "number is below its lower bound",
      )
    }
    Upper(bound, exclusive, location) => {
      guard value is Number(_, ..) else { return true }
      let ordering = numeric_value(value, path).compare(bound)
      (if exclusive { ordering < 0 } else { ordering <= 0 }) ||
      fail(
        failures,
        path,
        location,
        if exclusive {
          "exclusiveMaximum"
        } else {
          "maximum"
        },
        "number exceeds its upper bound",
      )
    }
    Multiple(divisor, location) => {
      guard value is Number(_, ..) else { return true }
      numeric_value(value, path).multiple_of(divisor) ||
      fail(
        failures, path, location, "multipleOf", "number is not an exact multiple",
      )
    }
    StringLength(minimum, maximum, location) => {
      guard value is String(text) else { return true }
      let length = text.char_length()
      let mut valid = true
      if minimum is Some(bound) && length < bound {
        valid = fail(
          failures,
          path,
          pointer_step(location, "minLength"),
          "minLength",
          "string has too few Unicode code points",
        )
        if failures is None {
          return false
        }
      }
      if maximum is Some(bound) && length > bound {
        valid = fail(
          failures,
          path,
          pointer_step(location, "maxLength"),
          "maxLength",
          "string has too many Unicode code points",
        )
      }
      valid
    }
    Pattern(pattern, location) => {
      guard value is String(text) else { return true }
      pattern_matches(pattern, text) ||
      fail(
        failures, path, location, "pattern", "string does not match the pattern",
      )
    }
    Objects(object_plan) =>
      evaluate_object(object_plan, value, path, failures, depth, limit)
    Arrays(array_plan) =>
      evaluate_array(array_plan, value, path, failures, depth, limit)
    All(branches, location) => {
      let mut valid = true
      for branch in branches {
        if !evaluate(branch, value, path, failures, depth + 1, limit) {
          valid = false
          if failures is None {
            return false
          }
        }
      }
      if !valid && failures is Some(_) {
        ignore(
          fail(failures, path, location, "allOf", "not every branch matched"),
        )
      }
      valid
    }
    Any(branches, location) => {
      for branch in branches {
        if evaluate(branch, value, path, None, depth + 1, limit) {
          return true
        }
      }
      fail(failures, path, location, "anyOf", "no branch matched")
    }
    One(branches, location) => {
      let mut matches = 0
      for branch in branches {
        if evaluate(branch, value, path, None, depth + 1, limit) {
          matches += 1
          if matches > 1 {
            break
          }
        }
      }
      matches == 1 ||
      fail(
        failures, path, location, "oneOf", "expected exactly one matching branch",
      )
    }
    Negate(branch, location) =>
      !evaluate(branch, value, path, None, depth + 1, limit) ||
      fail(failures, path, location, "not", "negated schema matched")
    Conditional(predicate, consequent, alternate) => {
      let arm = if evaluate(predicate, value, path, None, depth + 1, limit) {
        consequent
      } else {
        alternate
      }
      match arm {
        Some(branch) =>
          evaluate(branch, value, path, failures, depth + 1, limit)
        None => true
      }
    }
  }
}

///|
fn evaluate_object(
  plan : ObjectPlan,
  value : Json,
  path : String,
  failures : Array[Fault]?,
  depth : Int,
  limit : Int,
) -> Bool raise {
  guard value is Object(fields) else { return true }
  let mut valid = true
  if plan.minimum is Some(bound) && fields.length() < bound {
    valid = fail(
      failures,
      path,
      pointer_step(plan.path, "minProperties"),
      "minProperties",
      "object has too few properties",
    )
    if failures is None {
      return false
    }
  }
  if plan.maximum is Some(bound) && fields.length() > bound {
    valid = fail(
      failures,
      path,
      pointer_step(plan.path, "maxProperties"),
      "maxProperties",
      "object has too many properties",
    )
    if failures is None {
      return false
    }
  }
  for name in plan.required {
    if !fields.contains(name) {
      valid = fail(
        failures,
        path,
        pointer_step(plan.path, "required"),
        "required",
        "missing required property: " + name,
      )
      if failures is None {
        return false
      }
    }
  }
  // One property walk fuses properties, patternProperties and additionalProperties.
  for name, child in fields {
    let child_path = pointer_step(path, name)
    let mut covered = false
    if plan.properties.get(name) is Some(schema) {
      covered = true
      if !evaluate(schema, child, child_path, failures, depth + 1, limit) {
        valid = false
        if failures is None {
          return false
        }
      }
    }
    for entry in plan.patterns {
      let (pattern, schema) = entry
      if pattern_matches(pattern, name) {
        covered = true
        if !evaluate(schema, child, child_path, failures, depth + 1, limit) {
          valid = false
          if failures is None {
            return false
          }
        }
      }
    }
    if !covered && plan.additional is Some(schema) {
      if !evaluate(schema, child, child_path, failures, depth + 1, limit) {
        valid = false
        if failures is None {
          return false
        }
      }
    }
    if plan.names is Some(schema) {
      if !evaluate(
          schema,
          Json::string(name),
          child_path,
          failures,
          depth + 1,
          limit,
        ) {
        valid = false
        if failures is None {
          return false
        }
      }
    }
  }
  for entry in plan.dependent_required {
    let (trigger, names) = entry
    if fields.contains(trigger) {
      for name in names {
        if !fields.contains(name) {
          valid = fail(
            failures,
            path,
            pointer_step(pointer_step(plan.path, "dependentRequired"), trigger),
            "dependentRequired",
            "missing dependent property: " + name,
          )
          if failures is None {
            return false
          }
        }
      }
    }
  }
  for entry in plan.dependent_schemas {
    let (trigger, schema) = entry
    if fields.contains(trigger) &&
      !evaluate(schema, value, path, failures, depth + 1, limit) {
      valid = false
      if failures is None {
        return false
      }
    }
  }
  valid
}

///|
fn evaluate_array(
  plan : ArrayPlan,
  value : Json,
  path : String,
  failures : Array[Fault]?,
  depth : Int,
  limit : Int,
) -> Bool raise {
  guard value is Array(values) else { return true }
  let mut valid = true
  if plan.minimum is Some(bound) && values.length() < bound {
    valid = fail(
      failures,
      path,
      pointer_step(plan.path, "minItems"),
      "minItems",
      "array has too few items",
    )
    if failures is None {
      return false
    }
  }
  if plan.maximum is Some(bound) && values.length() > bound {
    valid = fail(
      failures,
      path,
      pointer_step(plan.path, "maxItems"),
      "maxItems",
      "array has too many items",
    )
    if failures is None {
      return false
    }
  }
  let mut matches = 0
  for index, child in values {
    let child_path = pointer_step(path, index.to_string())
    let schema = if index < plan.prefix.length() {
      Some(plan.prefix[index])
    } else {
      plan.items
    }
    if schema is Some(node) &&
      !evaluate(node, child, child_path, failures, depth + 1, limit) {
      valid = false
      if failures is None {
        return false
      }
    }
    if plan.contains is Some(node) &&
      evaluate(node, child, child_path, None, depth + 1, limit) {
      matches += 1
    }
    if plan.unique {
      for previous = 0; previous < index; previous = previous + 1 {
        if schema_equal(values[previous], child) {
          valid = fail(
            failures,
            child_path,
            pointer_step(plan.path, "uniqueItems"),
            "uniqueItems",
            "array contains equal items",
          )
          if failures is None {
            return false
          }
          break
        }
      }
    }
  }
  if plan.contains is Some(_) {
    if matches < plan.min_contains {
      valid = fail(
        failures,
        path,
        pointer_step(plan.path, "contains"),
        "contains",
        "too few items matched contains",
      )
      if failures is None {
        return false
      }
    }
    if plan.max_contains is Some(bound) && matches > bound {
      valid = fail(
        failures,
        path,
        pointer_step(plan.path, "maxContains"),
        "maxContains",
        "too many items matched contains",
      )
    }
  }
  valid
}
