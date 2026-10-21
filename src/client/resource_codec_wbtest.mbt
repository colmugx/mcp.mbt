///|
test "conformance: client resource reads preserve multiple contents without MIME defaults" {
  let contents : Array[Json] = [
    { "uri": "memo://1", "text": "hello", "_meta": {} },
    { "uri": "memo://2", "blob": "aGk=", "com.example/key": false },
  ]
  {
    let result = parse_read_resource({
      "contents": Json::array(contents),
      "ttlMs": 0,
      "cacheScope": "private",
      "_meta": {},
    })

    assert_eq(result.contents.map(@types.ResourceContents::to_json), contents)
    assert_eq(result.contents[1].mime_type, None)
    assert_eq(result.metadata.ttl_ms, Some(@types.JsonInteger::from_int(0)))
    assert_eq(result.metadata.meta, Some(Map([])))
  }
  try
    parse_read_resource({
      "contents": [
        { "uri": "memo://1", "text": "valid" },
        { "uri": "memo://2" },
      ],
    })
  catch {
    @types.InvalidParams(_) => ()
    error => raise error
  } noraise {
    _ => fail("expected malformed content to fail")
  }
}

///|
test "conformance: resource lists and templates preserve metadata and reject malformed entries" {
  let resource : Json = {
    "uri": "memo://1",
    "name": "memo",
    "title": "Memo",
    "icons": [],
    "annotations": {},
    "_meta": {},
  }
  {
    let result = parse_list_resources({
      "resources": [resource],
      "ttlMs": 0,
      "cacheScope": "private",
      "com.example/top": false,
    })

    assert_eq(result.resources[0].to_json(), resource)
    assert_eq(result.metadata.extensions.get("com.example/top"), Some(false))
  }
  let invalid : Array[Json] = [
    { "resources": [resource, { "uri": "memo://2" }] },
    { "resources": [resource], "nextCursor": false },
  ]
  for wire in invalid {
    try parse_list_resources(wire) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected malformed resource list to fail")
    }
  }
  {
    let result = parse_list_resource_templates({
      "resourceTemplates": [
        {
          "uriTemplate": "memo://{id}",
          "name": "memo",
          "icons": [],
          "annotations": {},
          "_meta": {},
        },
      ],
      "_meta": {},
    })

    assert_eq(result.resource_templates[0].icons, Some([]))
    assert_eq(result.resource_templates[0].metadata.meta, Some(Map([])))
    assert_eq(result.metadata.meta, Some(Map([])))
  }
  try
    parse_list_resource_templates({ "resourceTemplates": [{ "name": "memo" }] })
  catch {
    @types.InvalidParams(_) => ()
    error => raise error
  } noraise {
    _ => fail("expected malformed template to fail")
  }
}
