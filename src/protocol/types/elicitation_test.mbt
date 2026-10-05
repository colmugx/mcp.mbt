///|
test "elicitation form and URL modes round trip metadata and open fields" {
  for
    wire in [
      Json::object({
        "message": "name",
        "requestedSchema": {
          "type": "object",
          "properties": { "name": { "type": "string", "minLength": 1 } },
          "future": 2,
        },
        "_meta": { "trace": "form" },
        "future": null,
      }),
      Json::object({
        "message": "name",
        "mode": "form",
        "requestedSchema": { "type": "object", "properties": {} },
      }),
      Json::object({
        "message": "authorize",
        "mode": "url",
        "url": "https://example.org/auth",
        "elicitationId": "auth-1",
        "_meta": {},
        "future": [1],
      }),
    ] {
    assert_eq(@types.ElicitationRequest::from_json(wire).to_json(), wire)
  }
  assert_eq(
    @types.ElicitationRequest::form("name", {
      "type": "object",
      "properties": {},
    }).to_json(),
    {
      "message": "name",
      "requestedSchema": { "type": "object", "properties": {} },
    },
  )
  let url : Json = {
    "mode": "url",
    "message": "authorize",
    "url": "https://example.org",
  }
  assert_eq(@types.ElicitationRequest::from_json(url).to_json(), url)
  assert_eq(
    @types.ElicitationRequest::url("authorize", "https://example.org").to_json(),
    url,
  )
  assert_eq(
    @types.ElicitationRequest::url(
      "authorize",
      "https://example.org",
      elicitation_id="id",
    ).to_json(),
    {
      "mode": "url",
      "message": "authorize",
      "url": "https://example.org",
      "elicitationId": "id",
    },
  )
}

///|
test "elicitation results preserve all supported form values and absent content" {
  let wire : Json = {
    "action": "accept",
    "content": {
      "name": "test",
      "amount": 1.5,
      "enabled": false,
      "choices": ["a", "b"],
    },
    "_meta": { "future": true },
    "future": null,
  }
  assert_eq(@types.ElicitationResult::from_json(wire).to_json(), wire)
  for
    action in [
      @types.ElicitationAction::Accept,
      @types.ElicitationAction::Decline,
      @types.ElicitationAction::Cancel,
    ] {
    let result = @types.ElicitationResult::new(action)
    assert_false(
      result.to_json() is Object(fields) && fields.contains("content"),
    )
    assert_eq(
      @types.ElicitationResult::from_json(result.to_json()).action,
      action,
    )
  }
  assert_eq(
    @types.ElicitationResult::new(
      @types.ElicitationAction::Accept,
      content=Map([]),
    ).to_json(),
    { "action": "accept", "content": {} },
  )
}

///|
test "elicitation requests reject malformed modes and missing required mode fields" {
  for
    wire in [
      Json::object({ "mode": "future", "message": "x" }),
      Json::object({ "mode": "url", "message": "x" }),
      Json::object({
        "mode": "form",
        "message": "x",
        "requestedSchema": { "type": "array" },
      }),
      Json::object({ "message": "x", "requestedSchema": null }),
    ] {
    try @types.ElicitationRequest::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("malformed elicitation request must be rejected")
    }
  }
}

///|
test "elicitation results reject invalid actions and non-flat form data" {
  for
    wire in [
      Json::object({ "action": "dismiss" }),
      Json::object({ "action": "accept", "content": null }),
      Json::object({ "action": "accept", "content": { "nested": {} } }),
      Json::object({ "action": "accept", "content": { "array": ["a", 1] } }),
    ] {
    try @types.ElicitationResult::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("malformed elicitation result must be rejected")
    }
  }
}
