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
test "completion result roundtrip retains fractional totals and result metadata" {
  let wire : Json = {
    "completion": {
      "values": ["a", "b"],
      "total": 2147483648.5,
      "hasMore": false,
      "future": null,
    },
    "resultType": "complete",
    "_meta": { "trace": "kept" },
    "future": [1],
  }
  let result = @types.CompletionResult::from_json(wire)
  assert_eq(result.total, Some(2147483648.5))
  assert_eq(result.to_json(), wire)
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
