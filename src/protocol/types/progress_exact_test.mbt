///|
test "progress tokens preserve exact numeric identities and literals" {
  let literals = [
    "9007199254740992", "9007199254740993", "0.10000000000000000001", "1e100000000000000000000",
    "1e-100000000000000000000",
  ]
  let tokens = literals.map(literal => {
    @types.ProgressToken::ExactNumber(@types.JsonNumber::from_literal(literal))
  })
  for index in 0..<literals.length() {
    let token = @types.ProgressToken::from_json(tokens[index].to_json())
    assert_eq(token.to_json().stringify(), literals[index])
    assert_eq(token, tokens[index])
  }
  assert_true(tokens[0] != tokens[1])
  assert_true(tokens[2] != @types.ProgressToken::Number(0.1))
  assert_true(tokens[4] != @types.ProgressToken::Number(0))
  assert_eq(
    @types.ProgressToken::ExactNumber(
      @types.JsonNumber::from_literal("7.500e0"),
    ),
    @types.ProgressToken::Number(7.5),
  )
  assert_eq(
    @types.ProgressToken::ExactNumber(
      @types.JsonNumber::from_literal("-0.0e9999"),
    ),
    @types.ProgressToken::Number(0),
  )
  assert_true(tokens[1] != @types.ProgressToken::String(literals[1]))
}

///|
test "exact number tokens reject malformed or contradictory representations" {
  for
    value in [
      Json::number(0, repr="42"),
      Json::number(0, repr="01"),
      Json::number(0.0 / 0.0),
      Json::number(1.0 / 0.0),
    ] {
    try @types.ProgressToken::from_json(value) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("invalid numeric token must fail")
    }
  }
}
