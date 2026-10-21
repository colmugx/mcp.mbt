///|
test "exact protocol numbers retain decimal ordering without binary64 rounding" {
  for
    (left, right) in [
      ("9007199254740992", "9007199254740993"),
      ("1", "1.00000000000000000001"),
      ("-1e-400", "0"),
      ("0", "1e-400"),
      ("-100", "-99.99999999999999999999"),
      ("1e99999999999999999999", "2e99999999999999999999"),
    ] {
    let a = @types.JsonNumber::from_literal(left)
    let b = @types.JsonNumber::from_literal(right)
    assert_true(a.compare(b) < 0)
    assert_true(b.compare(a) > 0)
    assert_eq(a.compare(a), 0)
    assert_eq(a.to_json().stringify(), left)
  }
}

///|
test "protocol priority boundaries use exact decimals" {
  for literal in ["1.00000000000000000001", "-1e-400"] {
    let value = @types.JsonNumber::from_literal(literal).to_json()
    try @types.Annotations::from_json({ "priority": value }) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("out-of-range annotation priority must be rejected")
    }
    try @types.ModelPreferences::from_json({ "costPriority": value }) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("out-of-range sampling priority must be rejected")
    }
  }
}

///|
test "sampling rejects fractional token counts rather than rounding" {
  let value = @types.JsonNumber::from_literal("1024.00000000000000000001").to_json()
  try
    @types.CreateMessageRequest::from_json({
      "messages": [],
      "maxTokens": value,
    })
  catch {
    @types.InvalidParams(_) => ()
    error => raise error
  } noraise {
    _ => fail("maxTokens must be an integer according to the pinned schema")
  }
}

///|
test "elicitation and progress numeric values retain exact literals" {
  let value = @types.JsonNumber::from_literal(
    "9007199254740993.00000000000000000001",
  ).to_json()
  let elicitation = @types.ElicitationValue::from_json(value)
  assert_eq(elicitation.to_json().stringify(), value.stringify())
  let progress : Json = {
    "progressToken": "p",
    "progress": value,
    "total": value,
  }
  assert_eq(
    @types.ProgressNotification::from_json(progress).to_json().stringify(),
    progress.stringify(),
  )
}
