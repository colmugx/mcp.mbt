///|
test "conformance: prompt definitions and arguments round trip" {
  let wire : Json = {
    "name": "greet",
    "title": "Greet",
    "description": "",
    "icons": [],
    "_meta": {},
    "annotations": { "com.example/hint": false },
    "arguments": [
      {
        "name": "name",
        "title": "Name",
        "description": "",
        "required": false,
        "com.example/key": null,
      },
    ],
  }
  assert_eq(@types.PromptDefinition::from_json(wire).to_json(), wire)
  let minimal : Json = { "name": "greet" }
  assert_eq(@types.PromptDefinition::from_json(minimal).to_json(), minimal)
  assert_eq(
    @types.PromptDefinition::from_json({ "name": "greet", "arguments": [] }).to_json(),
    { "name": "greet", "arguments": [] },
  )
  assert_eq(@types.PromptArgument::new("name", required=false).to_json(), {
    "name": "name",
    "required": false,
  })
}

///|
test "conformance: prompt result preserves message extensions and result metadata" {
  let wire : Json = {
    "resultType": "complete",
    "description": "",
    "_meta": { "com.example/result": false },
    "com.example/top": null,
    "messages": [
      {
        "role": "user",
        "content": {
          "type": "audio",
          "data": "aGk=",
          "mimeType": "audio/wav",
          "_meta": {},
        },
        "com.example/message": [],
      },
      {
        "role": "assistant",
        "content": { "type": "future", "com.example/content": false },
      },
    ],
  }
  assert_eq(@types.GetPromptResult::from_json(wire).to_json(), wire)
  assert_eq(@types.GetPromptResult::new([]).to_json(), { "messages": [] })
  assert_eq(
    @types.PromptMessage::new(
      @types.Role::User,
      @types.ContentBlock::text("hello"),
    ).to_json(),
    { "role": "user", "content": { "type": "text", "text": "hello" } },
  )
}

///|
test "conformance: malformed prompt definitions and arguments fail" {
  let invalid : Array[Json] = [
    {},
    { "name": "greet", "title": false },
    { "name": "greet", "arguments": null },
    { "name": "greet", "arguments": [{ "name": "name", "required": "false" }] },
    { "name": "greet", "arguments": [{ "name": "valid" }, {}] },
    { "name": "greet", "icons": [null] },
    { "name": "greet", "_meta": [] },
  ]
  for wire in invalid {
    try @types.PromptDefinition::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected malformed prompt definition to fail")
    }
  }
}

///|
test "conformance: malformed prompt messages and results fail" {
  let invalid : Array[Json] = [
    {},
    { "messages": null },
    { "messages": [], "description": false },
    {
      "messages": [
        { "role": "system", "content": { "type": "text", "text": "hello" } },
      ],
    },
    { "messages": [{ "role": "user", "content": { "type": "text" } }] },
    { "messages": [null] },
    { "messages": [], "_meta": [] },
  ]
  for wire in invalid {
    try @types.GetPromptResult::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected malformed prompt result to fail")
    }
  }
}
