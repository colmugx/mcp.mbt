///|
test "conformance: client resource reads preserve multiple contents without MIME defaults" {
  let contents : Array[Json] = [
    { "uri": "memo://1", "text": "hello", "_meta": {} },
    { "uri": "memo://2", "blob": "aGk=", "com.example/key": false },
  ]
  match
    parse_read_resource({
      "contents": Json::array(contents),
      "ttlMs": 0,
      "cacheScope": "private",
      "_meta": {},
    }) {
    Ok(result) => {
      assert_eq(result.contents.map(@types.ResourceContents::to_json), contents)
      assert_eq(result.contents[1].mime_type, None)
      assert_eq(result.metadata.ttl_ms, Some(0.0))
      assert_eq(result.metadata.meta, Some(Map([])))
    }
    Err(error) => raise error
  }
  match
    parse_read_resource({
      "contents": [
        { "uri": "memo://1", "text": "valid" },
        { "uri": "memo://2" },
      ],
    }) {
    Err(@types.InvalidParams(_)) => ()
    Err(error) => raise error
    Ok(_) => fail("expected malformed content to fail")
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
  match
    parse_list_resources({
      "resources": [resource],
      "ttlMs": 0,
      "cacheScope": "private",
      "com.example/top": false,
    }) {
    Ok(result) => {
      assert_eq(result.resources[0].to_json(), resource)
      assert_eq(result.metadata.extensions.get("com.example/top"), Some(false))
    }
    Err(error) => raise error
  }
  let invalid : Array[Json] = [
    { "resources": [resource, { "uri": "memo://2" }] },
    { "resources": [resource], "nextCursor": false },
  ]
  for wire in invalid {
    match parse_list_resources(wire) {
      Err(@types.InvalidParams(_)) => ()
      Err(error) => raise error
      Ok(_) => fail("expected malformed resource list to fail")
    }
  }
  match
    parse_list_resource_templates({
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
    }) {
    Ok(result) => {
      assert_eq(result.resource_templates[0].icons, Some([]))
      assert_eq(result.resource_templates[0].metadata.meta, Some(Map([])))
      assert_eq(result.metadata.meta, Some(Map([])))
    }
    Err(error) => raise error
  }
  match
    parse_list_resource_templates({ "resourceTemplates": [{ "name": "memo" }] }) {
    Err(@types.InvalidParams(_)) => ()
    Err(error) => raise error
    Ok(_) => fail("expected malformed template to fail")
  }
}
