///|
test "conformance: resource definitions preserve all fields" {
  let wire : Json = {
    "uri": "memo://1",
    "name": "memo",
    "title": "Memo",
    "description": "Read a memo",
    "mimeType": "text/plain",
    "size": 0,
    "icons": [{ "src": "icon.png", "sizes": [] }],
    "annotations": { "priority": 0, "audience": [] },
    "_meta": {},
    "com.example/extension": false,
  }
  assert_eq(@types.ResourceDefinition::from_json(wire).to_json(), wire)
  let minimal : Json = { "uri": "memo://1", "name": "memo" }
  assert_eq(@types.ResourceDefinition::from_json(minimal).to_json(), minimal)
}

///|
test "conformance: resource templates preserve metadata and optional presence" {
  let wire : Json = {
    "uriTemplate": "memo://{id}",
    "name": "memo",
    "title": "",
    "description": "",
    "mimeType": "text/plain",
    "icons": [],
    "annotations": {},
    "_meta": {},
    "com.example/key": null,
  }
  assert_eq(@types.ResourceTemplateDefinition::from_json(wire).to_json(), wire)
  let minimal : Json = { "uriTemplate": "memo://{id}", "name": "memo" }
  assert_eq(
    @types.ResourceTemplateDefinition::from_json(minimal).to_json(),
    minimal,
  )
}

///|
test "conformance: resource read retains multiple text blob contents and metadata" {
  let wire : Json = {
    "resultType": "complete",
    "ttlMs": 0,
    "cacheScope": "private",
    "_meta": { "com.example/result": false },
    "com.example/top": [],
    "contents": [
      {
        "uri": "memo://1",
        "text": "hello",
        "mimeType": "text/plain",
        "_meta": {},
      },
      {
        "uri": "memo://2",
        "blob": "aGk=",
        "_meta": { "com.example/blob": null },
        "com.example/content": false,
      },
      { "uri": "memo://3", "text": "hello", "blob": "aGk=" },
    ],
  }
  let result = @types.ResourceReadResult::from_json(wire)
  assert_eq(result.contents.length(), 3)
  assert_eq(result.contents[1].mime_type, None)
  assert_eq(result.to_json(), wire)
  assert_eq(
    @types.ResourceReadResult::text("hello", uri="memo://1").to_json(),
    { "contents": [{ "uri": "memo://1", "text": "hello" }] },
  )
  assert_eq(@types.ResourceReadResult::blob("aGk=", uri="memo://2").to_json(), {
    "contents": [{ "uri": "memo://2", "blob": "aGk=" }],
  })
  assert_eq(
    @types.ResourceReadResult::from_json({ "contents": [] }).to_json(),
    { "contents": [] },
  )
}

///|
test "conformance: malformed resource contents fail instead of being filtered" {
  let invalid : Array[Json] = [
    {},
    { "contents": null },
    { "contents": [null] },
    { "contents": [{ "uri": "memo://1" }] },
    { "contents": [{ "uri": "memo://1", "blob": "aGk=", "mimeType": false }] },
    {
      "contents": [
        { "uri": "memo://1", "text": "valid" },
        { "text": "missing URI" },
      ],
    },
  ]
  for wire in invalid {
    try @types.ResourceReadResult::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected malformed resource contents to fail")
    }
  }
}

///|
test "conformance: malformed resource definition fields fail" {
  let invalid : Array[Json] = [
    { "uri": "memo://1" },
    { "uri": "memo://1", "name": "memo", "size": 0.5 },
    { "uri": "memo://1", "name": "memo", "annotations": null },
    { "uri": "memo://1", "name": "memo", "icons": [null] },
    { "uri": "memo://1", "name": "memo", "mimeType": false },
  ]
  for wire in invalid {
    try @types.ResourceDefinition::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected malformed resource definition to fail")
    }
  }
}
