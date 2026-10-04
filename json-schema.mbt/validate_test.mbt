///|
fn compiled(text : String) -> @json-schema.Schema raise {
  @json-schema.Schema::compile(@json-schema.parse(text))
}

///|
test "diagnostics: pointers escape every segment; speculative branches stay isolated" {
  let schema = compiled("{\"properties\":{\"a~/b~/\":{\"type\":\"string\"}}}")
  let failures = schema.faults(@json-schema.parse("{\"a~/b~/\":1}"))
  assert_eq(failures.length(), 1)
  assert_eq(failures[0].instance_path, "/a~0~1b~0~1")
  assert_eq(failures[0].schema_path, "/properties/a~0~1b~0~1/type")
  assert_eq(failures[0].keyword, "type")
  let speculative = compiled(
    "{\"anyOf\":[false,true],\"not\":false,\"if\":false,\"then\":false}",
  )
  assert_eq(speculative.faults(Json::null()).length(), 0)
}

///|
test "ownership: compiled constants do not alias caller maps" {
  let constant : Map[String, Json] = { "a": Json::number(1) }
  let schema = @json-schema.Schema::compile(
    Json::object({ "const": Json::object(constant) }),
  )
  constant.set("a", Json::number(2))
  assert_true(schema.valid(@json-schema.parse("{\"a\":1}")))
  assert_false(schema.valid(@json-schema.parse("{\"a\":2}")))
}

///|
test "compiler: malformed keyword shapes and unavailable semantics are typed errors" {
  for
    source in [
      "null", "1", "{\"type\":123}", "{\"type\":[]}", "{\"type\":[\"string\",\"string\"]}",
      "{\"multipleOf\":0}", "{\"minimum\":\"1\"}", "{\"minLength\":-1}", "{\"minItems\":1.5}",
      "{\"required\":[\"a\",\"a\"]}", "{\"properties\":[]}", "{\"patternProperties\":[]}",
      "{\"items\":[]}", "{\"prefixItems\":[]}", "{\"uniqueItems\":1}", "{\"anyOf\":[]}",
      "{\"then\":null}", "{\"dependentRequired\":{\"x\":false}}", "{\"$defs\":{\"x\":null}}",
    ] {
    try compiled(source) catch {
      @json-schema.CompileError::InvalidKeyword(..) => ()
      error => raise error
    } noraise {
      _ => fail("expected InvalidKeyword: " + source)
    }
  }
  try compiled("{\"$ref\":\"#/x\"}") catch {
    @json-schema.CompileError::UnsupportedKeyword(keyword~, ..) =>
      assert_eq(keyword, "$ref")
    error => raise error
  } noraise {
    _ => fail("expected unsupported reference")
  }
}

///|
test "budgets: traversal and invalid numeric nodes raise rather than mismatch" {
  let schema = compiled("true")
  try
    schema.valid(Json::array([Json::array([Json::null()])]), max_depth=1)
  catch {
    @json-schema.EvaluationError::DepthLimit(_) => ()
    error => raise error
  } noraise {
    _ => fail("expected instance depth limit")
  }
  try schema.valid(Json::number(0.0 / 0.0)) catch {
    @json-schema.EvaluationError::InvalidNumber(..) => ()
    error => raise error
  } noraise {
    _ => fail("expected invalid numeric node")
  }
  try
    @json-schema.Schema::compile(
      @json-schema.parse("{\"const\":[[1]]}"),
      max_depth=1,
    )
  catch {
    @json-schema.CompileError::DepthLimit(_) => ()
    error => raise error
  } noraise {
    _ => fail("expected schema depth limit")
  }
}
