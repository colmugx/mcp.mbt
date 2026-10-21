///|
test "exact JSON integers preserve wire spelling and compare mathematical identities" {
  for
    (literal, canonical) in [
      ("0", "0e0"),
      ("-0.00e-999999999999999999999", "0e0"),
      ("12300", "123e2"),
      ("1.2300e4", "123e2"),
      ("-2147483648", "-2147483648e0"),
      ("9007199254740993", "9007199254740993e0"),
      ("1e100000000000000000000", "1e100000000000000000000"),
    ] {
    let integer = @types.JsonInteger::from_literal(literal)
    assert_eq(integer.to_json_string(), literal)
    assert_eq(integer.key(), canonical)
  }
  assert_eq(
    @types.JsonInteger::from_literal("1.2300e4"),
    @types.JsonInteger::from_literal("12300"),
  )
  assert_eq(
    @types.JsonInteger::from_literal("2147483647").as_int(),
    Some(2147483647),
  )
  assert_eq(
    @types.JsonInteger::from_literal("-2147483648").as_int(),
    Some(-2147483648),
  )
  assert_eq(@types.JsonInteger::from_literal("2147483648").as_int(), None)
  assert_eq(@types.JsonInteger::from_literal("9007199254740993").as_int(), None)
}

///|
test "integer wire decoders reject fractions and malformed numeric reprs" {
  for
    literal in [
      "", "01", "+1", "1.", "1e", "1e+", " 1", "1 ", "1.5", "1e-1", "1.00000000000000000001",
      "null",
    ] {
    try @types.JsonInteger::from_json(Json::number(1, repr=literal)) catch {
      @types.InvalidRequest(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("invalid integer literal accepted: " + literal)
    }
  }
  for
    value in [
      Json::number(0.5),
      Json::number(0, repr="42"),
      Json::number(0.0 / 0.0, repr="0"),
      Json::number(1.0 / 0.0),
      Json::number(1.0 / 0.0, repr="1"),
      Json::null(),
      Json::boolean(true),
      Json::array([]),
      Json::object({}),
    ] {
    try @types.RequestId::from_json(value) catch {
      @types.InvalidRequest(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("invalid request id accepted")
    }
  }
}

///|
test "request ids distinguish strings from numbers and preserve integers beyond binary64" {
  let first = @types.RequestId::from_json(
    @types.JsonInteger::from_literal("9007199254740992").to_json(),
  )
  let second = @types.RequestId::from_json(
    @types.JsonInteger::from_literal("9007199254740993").to_json(),
  )
  assert_false(first == second)
  assert_false(first.key() == second.key())
  assert_eq(second.to_json_string(), "9007199254740993")
  assert_false(@types.RequestId::Int(42) == @types.RequestId::Str("42"))
  assert_eq(
    @types.RequestId::from_json(
      @types.JsonInteger::from_literal("4.2e1").to_json(),
    ),
    @types.RequestId::Int(42),
  )
  assert_eq(@types.RequestId::Str("\"\\\n").to_json_string(), "\"\\\"\\\\\\n\"")
  let wire = Json::object({
    "jsonrpc": "2.0",
    "id": second.to_json(),
    "method": "tools/list",
  })
  assert_eq(@types.JsonRpcRequest::from_json(wire).id, second)
  try
    @types.JsonRpcRequest::from_json(
      Json::object({ "jsonrpc": "2.0", "id": 1.5, "method": "tools/list" }),
    )
  catch {
    @types.InvalidRequest(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid request ID")
  }
}
