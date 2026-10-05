///|
fn form_request(schema : Json) -> Json {
  { "message": "Choose", "requestedSchema": schema }
}

///|
test "elicitation validators enforce primitive and titled multi-select form constraints" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "name": { "type": "string", "minLength": 2, "maxLength": 4 },
      "age": { "type": "integer", "minimum": 1, "maximum": 10 },
      "enabled": { "type": "boolean" },
      "color": {
        "type": "string",
        "oneOf": [
          { "const": "red", "title": "Red" },
          { "const": "blue", "title": "Blue" },
        ],
      },
      "choices": {
        "type": "array",
        "minItems": 1,
        "maxItems": 2,
        "items": {
          "anyOf": [
            { "const": "a", "title": "A" },
            { "const": "b", "title": "B" },
          ],
        },
      },
    },
    "required": ["name", "age", "enabled", "color", "choices"],
  }
  let validator = @validation.ElicitationValidator::compile(
    form_request(schema),
  )
  let content : Json = {
    "name": "Ada",
    "age": 5,
    "enabled": false,
    "color": "red",
    "choices": ["a", "b"],
  }
  validator.check_response({ "action": "accept", "content": content })
  for
    invalid in [
      Json::object({}),
      Json::object({
        "name": "A",
        "age": 5,
        "enabled": false,
        "color": "red",
        "choices": ["a"],
      }),
      Json::object({
        "name": "Ada",
        "age": 1.5,
        "enabled": false,
        "color": "red",
        "choices": ["a"],
      }),
      Json::object({
        "name": "Ada",
        "age": 5,
        "enabled": false,
        "color": "green",
        "choices": ["a"],
      }),
      Json::object({
        "name": "Ada",
        "age": 5,
        "enabled": false,
        "color": "red",
        "choices": ["c"],
      }),
    ] {
    try
      validator.check_response({ "action": "accept", "content": invalid })
    catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("invalid form must fail")
    }
  }
}

///|
test "elicitation validates action and mode before allowing content" {
  let form = @validation.ElicitationValidator::compile(
    form_request({ "type": "object", "properties": {} }),
  )
  let url = @validation.ElicitationValidator::compile({
    "mode": "url",
    "message": "Authorize",
    "url": "https://example.org",
  })
  form.check_response({ "action": "accept", "content": {} })
  for action in ["decline", "cancel"] {
    form.check_response({ "action": action })
  }
  for action in ["accept", "decline", "cancel"] {
    url.check_response({ "action": action })
    try url.check_response({ "action": action, "content": {} }) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("URL response must omit content")
    }
  }
  for
    response in [
      Json::object({ "action": "accept" }),
      Json::object({ "action": "cancel", "content": {} }),
      Json::object({ "action": "decline", "content": {} }),
    ] {
    try form.check_response(response) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("invalid action/content combination")
    }
  }
}

///|
test "elicitation request decoding rejects malformed restricted schemas before compilation" {
  for
    schema in [
      Json::object({ "type": "object" }),
      Json::object({
        "type": "object",
        "properties": { "nested": { "type": "object" } },
      }),
      Json::object({
        "type": "object",
        "properties": {
          "list": { "type": "array", "items": { "type": "string" } },
        },
      }),
      Json::object({
        "type": "object",
        "properties": {
          "pick": { "type": "string", "oneOf": [{ "const": "a" }] },
        },
      }),
      Json::object({
        "type": "object",
        "properties": { "n": { "type": "number", "default": "1" } },
      }),
      Json::object({ "type": "object", "properties": {}, "required": [1] }),
      Json::object({
        "type": "object",
        "properties": { "s": { "type": "string", "format": "future" } },
      }),
    ] {
    try @types.ElicitationRequest::from_json(form_request(schema)) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("restricted schema must be rejected")
    }
  }
  for
    property in [
      Json::object({ "type": "string", "minLength": -1 }),
      Json::object({ "type": "string", "$dynamicRef": "#a" }),
    ] {
    try
      @validation.ElicitationValidator::compile(
        form_request({ "type": "object", "properties": { "s": property } }),
      )
    catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("invalid or unsupported constraints must fail closed")
    }
  }
}

///|
test "elicitation validators own a snapshot and retain exact decimal comparisons" {
  let properties : Map[String, Json] = {
    "amount": {
      "type": "number",
      "maximum": @validation.parse_json("0.1000000000000000000000000000001"),
    },
  }
  let validator = @validation.ElicitationValidator::compile(
    form_request({
      "type": "object",
      "properties": Json::object(properties),
      "required": ["amount"],
    }),
  )
  properties["amount"] = { "type": "number" }
  validator.check_response(
    @validation.parse_json(
      "{\"action\":\"accept\",\"content\":{\"amount\":0.1000000000000000000000000000001}}",
    ),
  )
  try
    validator.check_response(
      @validation.parse_json(
        "{\"action\":\"accept\",\"content\":{\"amount\":0.1000000000000000000000000000002}}",
      ),
    )
  catch {
    @types.InvalidParams(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("must not round distinct decimal values together")
  }
}
