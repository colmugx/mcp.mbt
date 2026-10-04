///|
test "conformance: all content blocks round-trip metadata and extensions" {
  let fixtures : Array[Json] = [
    {
      "type": "text",
      "text": "hello\n世界",
      "annotations": {
        "audience": [],
        "priority": 0,
        "lastModified": "2026-07-28T00:00:00Z",
        "vendor": false,
      },
      "_meta": { "com.example/tag": null },
      "vendor": [1, { "nested": true }],
    },
    {
      "type": "image",
      "data": "aGk=",
      "mimeType": "image/png",
      "annotations": { "audience": ["user", "assistant"], "priority": 1 },
      "_meta": {},
    },
    {
      "type": "audio",
      "data": "aGk=",
      "mimeType": "audio/wav",
      "annotations": {},
      "_meta": {},
    },
    {
      "type": "resource_link",
      "uri": "memo://1",
      "name": "memo",
      "title": "Memo",
      "description": "",
      "mimeType": "text/plain",
      "size": 0,
      "icons": [
        {
          "src": "data:image/png;base64,aGk=",
          "mimeType": "image/png",
          "sizes": [],
          "theme": "dark",
          "vendor": null,
        },
      ],
      "annotations": { "priority": 0.25 },
      "_meta": { "key": false },
      "vendor": {},
    },
    {
      "type": "resource",
      "resource": {
        "uri": "memo://2",
        "text": "body",
        "mimeType": "text/plain",
        "_meta": {},
        "annotations": { "priority": 0.5 },
      },
      "annotations": { "audience": ["assistant"] },
      "_meta": {},
    },
    {
      "type": "resource",
      "resource": {
        "uri": "memo://3",
        "blob": "aGk=",
        "_meta": { "key": null },
      },
    },
    {
      "type": "future_video",
      "data": [1, 2],
      "annotations": { "future": null },
      "_meta": {},
      "extra": false,
    },
  ]
  for wire in fixtures {
    let decoded = @types.ContentBlock::from_json(wire)
    assert_eq(decoded.to_json(), wire)
    assert_eq(@types.ContentBlock::from_json(decoded.to_json()), decoded)
  }
}

///|
test "conformance: unknown type is retained rather than filtered out" {
  let wire : Json = {
    "type": "future",
    "fields": { "null": null, "false": false, "empty": [] },
  }
  let block = @types.ContentBlock::from_json(wire)
  match block {
    Unknown(value) => assert_eq(value, wire)
    _ => fail("expected Unknown")
  }
  guard block.to_json() is Object(encoded) else {
    fail("expected encoded object")
  }
  encoded.set("type", Json::string("changed"))
  assert_eq(block.to_json(), wire)
}

///|
test "conformance: malformed known content is rejected" {
  let invalid : Array[Json] = [
    null,
    {},
    { "type": 1 },
    { "type": "text" },
    { "type": "text", "text": 1 },
    { "type": "image", "data": "aGk=" },
    { "type": "audio", "data": "aGk=", "mimeType": null },
    { "type": "resource_link", "uri": "memo://1" },
    { "type": "resource", "resource": { "uri": "memo://1" } },
    { "type": "resource", "resource": { "blob": "aGk=" } },
    { "type": "text", "text": "t", "_meta": null },
    { "type": "text", "text": "t", "annotations": [] },
    { "type": "text", "text": "t", "annotations": { "audience": ["system"] } },
    { "type": "text", "text": "t", "annotations": { "priority": -0.1 } },
    { "type": "text", "text": "t", "annotations": { "priority": 1.1 } },
    { "type": "resource_link", "uri": "memo://1", "name": "memo", "size": 0.5 },
  ]
  for wire in invalid {
    try @types.ContentBlock::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected malformed content to fail")
    }
  }
}

///|
test "conformance: embedded resource union preserves alternate fields" {
  let fixtures : Array[Json] = [
    {
      "type": "resource",
      "resource": { "uri": "memo://1", "text": "text", "blob": "aGk=" },
    },
    {
      "type": "resource",
      "resource": { "uri": "memo://1", "text": 1, "blob": "aGk=" },
    },
  ]
  for wire in fixtures {
    assert_eq(@types.ContentBlock::from_json(wire).to_json(), wire)
  }
}

///|
test "conformance: empty metadata is distinct from absent metadata" {
  let absent : Json = { "type": "text", "text": "t" }
  let present : Json = {
    "type": "text",
    "text": "t",
    "annotations": {},
    "_meta": {},
  }
  let a = @types.ContentBlock::from_json(absent)
  let b = @types.ContentBlock::from_json(present)
  assert_true(a != b)
  assert_eq(a.to_json(), absent)
  assert_eq(b.to_json(), present)
}

///|
test "conformance: serialization does not mutate extension or input maps" {
  let fields : Map[String, Json] = {
    "type": "text",
    "text": "t",
    "_meta": {},
    "vendor": false,
  }
  let before = Json::object(fields).stringify()
  let decoded = @types.ContentBlock::from_json(Json::object(fields))
  ignore(decoded.to_json())
  assert_eq(Json::object(fields).stringify(), before)
  let extensions : Map[String, Json] = {
    "type": "collision",
    "text": false,
    "_meta": null,
    "vendor": [],
  }
  let before_extensions = Json::object(extensions).stringify()
  let block = @types.ContentBlock::text("t", metadata={
    annotations: None,
    meta: None,
    extensions,
  })
  assert_eq(block.to_json(), { "type": "text", "text": "t", "vendor": [] })
  assert_eq(Json::object(extensions).stringify(), before_extensions)
}

///|
test "conformance: typed content constructors use shared codecs" {
  assert_eq(@types.ContentBlock::text("t").to_json(), {
    "type": "text",
    "text": "t",
  })
  assert_eq(
    @types.ContentBlock::image("aGk=", mime_type="image/png").to_json(),
    { "type": "image", "data": "aGk=", "mimeType": "image/png" },
  )
  assert_eq(
    @types.ContentBlock::audio("aGk=", mime_type="audio/wav").to_json(),
    { "type": "audio", "data": "aGk=", "mimeType": "audio/wav" },
  )
  assert_eq(
    @types.ContentBlock::resource_link("memo://1", name="memo").to_json(),
    { "type": "resource_link", "uri": "memo://1", "name": "memo" },
  )
  assert_eq(
    @types.ContentBlock::resource(
      @types.ResourceContents::blob("aGk=", uri="memo://1"),
    ).to_json(),
    { "type": "resource", "resource": { "uri": "memo://1", "blob": "aGk=" } },
  )
}

///|
test "conformance: icons retain optional and extension fields" {
  let fixtures : Array[Json] = [
    { "src": "data:image/png;base64,aGk=" },
    {
      "src": "data:image/png;base64,aGk=",
      "theme": "light",
      "sizes": ["any"],
      "mimeType": "image/png",
      "extra": null,
    },
  ]
  for wire in fixtures {
    assert_eq(@types.Icon::from_json(wire).to_json(), wire)
  }
  let invalid : Array[Json] = [
    {},
    { "src": "x", "theme": "other" },
    { "src": "x", "sizes": [1] },
  ]
  for wire in invalid {
    try @types.Icon::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected invalid icon to fail")
    }
  }
}
