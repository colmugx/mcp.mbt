///|
fn exact(text : String) -> @json-schema.ExactNumber {
  @json-schema.ExactNumber::from_literal(text).unwrap()
}

///|
test "numeric: aligned coefficients preserve arbitrary decimal digits" {
  assert_true(exact("0.3").multiple_of(exact("0.1")))
  assert_true(exact("-0.3").multiple_of(exact("0.1")))
  assert_false(exact("1.00000000000000000000000000001").multiple_of(exact("1")))
  assert_false(exact("1000000000.5").multiple_of(exact("1")))
  assert_true(
    exact("900719925474099300").multiple_of(exact("9007199254740993")),
  )
  assert_false(
    exact("900719925474099301").multiple_of(exact("9007199254740993")),
  )
  assert_eq(exact("9007199254740993").compare(exact("9007199254740992")), 1)
  assert_true(exact("1e400").equal(exact("10e399")))
  assert_true(exact("1e-400").equal(exact("0.1e-399")))
  assert_true(exact("-0").equal(exact("0.000")))
  assert_true(exact("3.0e1").is_integer())
  assert_false(exact("1e-400").is_integer())
}

///|
test "numeric: invalid literals and inconsistent repr are not silently ignored" {
  for text in ["", "01", "NaN", "Infinity", "+1", "1e", "1.", "1e100001"] {
    assert_true(@json-schema.ExactNumber::from_literal(text) is None, msg=text)
  }
  assert_true(
    @json-schema.ExactNumber::of_json(Json::number(1, repr="2")) is None,
  )
  assert_true(
    @json-schema.ExactNumber::of_json(Json::number(1, repr="bad")) is None,
  )
  assert_true(
    @json-schema.ExactNumber::of_json(Json::number(1.0 / 0.0)) is None,
  )
  assert_true(
    @json-schema.ExactNumber::of_json(Json::number(0.0 / 0.0)) is None,
  )
  let invalid = @json-schema.ExactNumber::from_double(0.0 / 0.0)
  let raised = try {
    ignore(invalid.compare(exact("1")))
    false
  } catch {
    @json-schema.NumericError::InvalidNumber => true
  }
  assert_true(raised)
  assert_true(
    @json-schema.ExactNumber::from_double(0.3).multiple_of(exact("0.1")),
  )
}

///|
test "numeric: const enum and uniqueItems use nested exact equality" {
  let constant = @json-schema.Schema::compile(
    @json-schema.parse("{\"const\":{\"n\":[9007199254740993]}}"),
  )
  assert_true(
    constant.valid(@json-schema.parse("{\"n\":[9007199254740993.0]}")),
  )
  assert_false(constant.valid(@json-schema.parse("{\"n\":[9007199254740992]}")))
  let enumeration = @json-schema.Schema::compile(
    @json-schema.parse("{\"enum\":[9007199254740993]}"),
  )
  assert_false(enumeration.valid(@json-schema.parse("9007199254740992")))
  let unique = @json-schema.Schema::compile(
    @json-schema.parse("{\"uniqueItems\":true}"),
  )
  assert_true(
    unique.valid(@json-schema.parse("[9007199254740992,9007199254740993]")),
  )
  assert_false(
    unique.valid(@json-schema.parse("[9007199254740993,9007199254740993.0]")),
  )
}
