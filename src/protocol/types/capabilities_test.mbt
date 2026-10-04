///|
test "client capability codecs preserve optional objects and unknown fields" {
  let wire : Json = {
    "experimental": { "future": { "version": 2 } },
    "roots": { "custom": null },
    "sampling": {
      "context": { "policy": "local" },
      "tools": {},
      "future": false,
    },
    "elicitation": { "form": {}, "url": { "schemes": ["https"] } },
    "extensions": { "example.org/feature": {} },
    "future": [1, 2],
  }
  assert_eq(@types.ClientCapabilities::from_json(wire).to_json(), wire)
  assert_eq(@types.ClientCapabilities::new().to_json(), Json::object({}))
  assert_eq(
    @types.ClientCapabilities::from_json({ "elicitation": {} }).to_json(),
    Json::object({ "elicitation": {} }),
  )
}

///|
test "server capabilities preserve completions logging and optional false versus absence" {
  let wire : Json = {
    "experimental": { "future": {} },
    "logging": { "level": "info" },
    "completions": {},
    "tools": { "listChanged": false, "future": 3 },
    "resources": { "subscribe": true },
    "prompts": {},
    "extensions": { "example.org/feature": {} },
    "future": null,
  }
  let value = @types.ServerCapabilities::from_json(wire)
  assert_eq(value.to_json(), wire)
  assert_true(value.completions is Some(_))
  assert_eq(value.tools.unwrap().list_changed, Some(false))
  assert_eq(value.resources.unwrap().list_changed, None)
}

///|
test "capability decoders reject malformed known fields instead of advertising support" {
  for
    wire in [
      Json::object({ "sampling": true }),
      Json::object({ "elicitation": { "form": true } }),
      Json::object({ "sampling": { "tools": null } }),
      Json::object({ "experimental": { "x": 1 } }),
      Json::object({ "extensions": { "example.org/x": false } }),
    ] {
    try @types.ClientCapabilities::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("malformed capability must be rejected")
    }
  }
  try
    @types.ServerCapabilities::from_json({ "tools": { "listChanged": null } })
  catch {
    @types.InvalidParams(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("invalid boolean must be rejected")
  }
}

///|
test "missing required capability error emits a capability object rather than a string array" {
  let error = @types.MissingRequiredClientCapability(
    "sampling tools required",
    required=@types.ClientCapabilities::new(
      sampling=@types.SamplingCapabilities::new(tools={}),
    ),
  )
  assert_eq(
    error.to_error_data(),
    Some(
      Json::object({ "requiredCapabilities": { "sampling": { "tools": {} } } }),
    ),
  )
}
