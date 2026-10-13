///|
test "completion params preserve reference context argument metadata and extension fields" {
  for
    reference in [
      Json::object({
        "type": "ref/prompt",
        "name": "review",
        "title": "Review",
        "future": true,
      }),
      Json::object({
        "type": "ref/resource",
        "uri": "memo://{id}",
        "future": [],
      }),
    ] {
    let wire : Json = {
      "ref": reference,
      "argument": { "name": "id", "value": "a", "future": 1 },
      "context": { "arguments": { "locale": "zh" }, "future": false },
      "_meta": { "trace": "kept" },
      "future": null,
    }
    assert_eq(@types.CompleteRequestParams::from_json(wire).to_json(), wire)
  }
}

///|
test "completion result roundtrip retains exact integer totals and result metadata" {
  let wire : Json = {
    "completion": {
      "values": ["a", "b"],
      "total": @types.JsonInteger::from_literal("9007199254740993").to_json(),
      "hasMore": false,
      "future": null,
    },
    "resultType": "complete",
    "_meta": { "trace": "kept" },
    "future": [1],
  }
  let result = @types.CompletionResult::from_json(wire)
  assert_eq(
    result.total,
    Some(@types.JsonInteger::from_literal("9007199254740993")),
  )
  assert_eq(result.to_json(), wire)
  assert_eq(@types.CompletionResult::new(["a"], total=2).to_json(), {
    "completion": { "values": ["a"], "total": 2 },
  })
}

///|
test "completion totals are integers: fractional wire totals are rejected" {
  for
    total in [
      "2147483648.5", "9007199254740992.5", "1e-1", "2.00000000000000000001",
    ] {
    let wire : Json = {
      "completion": {
        "values": ["a"],
        "total": @types.JsonNumber::from_literal(total).to_json(),
      },
      "resultType": "complete",
    }
    try @types.CompletionResult::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("fractional completion total must be rejected: " + total)
    }
  }
}

///|
test "completion rejects malformed entries and more than one hundred values" {
  for
    wire in [
      Json::object({ "completion": { "values": [1] } }),
      Json::object({ "completion": { "values": [], "hasMore": null } }),
      Json::object({
        "completion": { "values": Array::make(101, Json::string("x")) },
      }),
    ] {
    try @types.CompletionResult::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("malformed completion must be rejected, not truncated")
    }
  }
  try
    @types.CompleteRequestParams::from_json({
      "ref": { "type": "ref/resource", "name": "wrong field" },
      "argument": { "name": "id", "value": "a" },
    })
  catch {
    @types.InvalidParams(_) => ()
    error => raise error
  } noraise {
    _ => fail("resource reference requires uri")
  }
}
