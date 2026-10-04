///|
test "parse: preserve numeric lexemes recursively and last duplicate key" {
  let value = @json-schema.parse(
    "{\"n\":1.2300e+2,\"a\":[-0,9007199254740993],\"n\":2.00}",
  )
  guard! value is Object(fields)
  guard! fields["n"] is Number(_, repr=Some(representation))
  assert_eq(representation, "2.00")
  guard! fields["a"] is Array(values)
  guard! values[0] is Number(_, repr=Some(zero))
  guard! values[1] is Number(_, repr=Some(big))
  assert_eq(zero, "-0")
  assert_eq(big, "9007199254740993")
  assert_eq(values[1].stringify(), "9007199254740993")
  assert_eq(@json-schema.parse("1e400").stringify(), "1e400")
  assert_eq(@json-schema.parse("1e-400").stringify(), "1e-400")
}

///|
test "parse: strings, escapes, whitespace and nested JSON" {
  let value = @json-schema.parse(
    " \t\r\n{\"text\":\"😀\\n\\u0041\\\"\\\\\",\"a\":[true,false,null,{}]} \n",
  )
  guard! value is Object(fields)
  assert_eq(fields["text"], Json::string("😀\nA\"\\"))
  guard! fields["a"] is Array(values)
  assert_eq(values.length(), 4)
}

///|
test "parse: malformed JSON rejected without recovery" {
  for
    source in [
      "", " ", "01", "-", "+1", ".1", "1.", "1e", "1e+", "NaN", "Infinity", "true false",
      "nullx", "[1,]", "[,1]", "{\"x\":}", "{\"x\":1,}", "{x:1}", "\"\\x00\"", "\"unterminated",
      "\"raw\nline\"", "[[]",
    ] {
    let failed = try {
      ignore(@json-schema.parse(source))
      false
    } catch {
      _ => true
    }
    assert_true(failed, msg=source)
  }
  let too_deep = try {
    ignore(@json-schema.parse("[[null]]", max_nesting_depth=1))
    false
  } catch {
    @json-schema.ParseError::DepthLimit(_) => true
    _ => false
  }
  assert_true(too_deep)
}

///|
test "parse: high precision values affect validation, not rounded doubles" {
  let maximum = @json-schema.Schema::compile(
    @json-schema.parse("{\"maximum\":9007199254740992}"),
  )
  assert_false(maximum.valid(@json-schema.parse("9007199254740993")))
  let integer = @json-schema.Schema::compile(
    @json-schema.parse("{\"type\":\"integer\",\"multipleOf\":1}"),
  )
  assert_false(
    integer.valid(@json-schema.parse("1.00000000000000000000000000001")),
  )
  assert_true(integer.valid(@json-schema.parse("1e400")))
  let positive = @json-schema.Schema::compile(
    @json-schema.parse("{\"exclusiveMinimum\":0}"),
  )
  assert_true(positive.valid(@json-schema.parse("1e-400")))
  assert_false(positive.valid(@json-schema.parse("-0")))
}
