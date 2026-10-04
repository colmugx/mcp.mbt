///|
test "conformance: tool result retains audio blob unknown and metadata" {
  let items : Array[Json] = [
    {
      "type": "audio",
      "data": "aGk=",
      "mimeType": "audio/wav",
      "annotations": {},
      "_meta": {},
    },
    {
      "type": "resource",
      "resource": {
        "uri": "memo://1",
        "blob": "aGk=",
        "_meta": { "com.example/key": false },
      },
    },
    { "type": "future", "extra": [null, false] },
  ]
  match parse_call_tool({ "content": Json::array(items), "isError": false }) {
    Ok(result) => {
      assert_eq(result.content.length(), 3)
      assert_eq(result.content.map(item => item.to_json()), items)
      assert_eq(result.is_error, Some(false))
    }
    Err(error) => raise error
  }
}

///|
test "conformance: client retains structured output and result metadata" {
  let wire : Json = {
    "content": [],
    "structuredContent": null,
    "resultType": "complete",
    "_meta": { "com.example/key": false },
    "com.example/extension": [],
  }
  match parse_call_tool(wire) {
    Ok(result) => {
      assert_eq(result.structured_content, Some(null))
      assert_eq(result.is_error, None)
      assert_eq(
        result.metadata.meta.unwrap().get("com.example/key"),
        Some(false),
      )
      assert_eq(
        result.metadata.extensions.get("com.example/extension"),
        Some([]),
      )
    }
    Err(error) => raise error
  }
}

///|
test "conformance: client tool list rejects malformed definitions rather than dropping them" {
  let wire : Json = {
    "tools": [
      { "name": "valid", "inputSchema": { "type": "object" } },
      { "name": "invalid", "inputSchema": {} },
    ],
  }
  match parse_tools_list(wire) {
    Err(@types.InvalidParams(_)) => ()
    Err(error) => raise error
    Ok(_) => fail("expected malformed tool definition to fail")
  }
  let definition : Json = {
    "name": "valid",
    "inputSchema": { "type": "object" },
    "outputSchema": { "type": "string" },
    "annotations": {},
    "_meta": {},
    "com.example/key": null,
  }
  match parse_tools_list({ "tools": [definition] }) {
    Ok(result) => assert_eq(result.tools[0].to_json(), definition)
    Err(error) => raise error
  }
}

///|
test "conformance: invalid tool content fails instead of dropping items" {
  let invalid : Array[Json] = [
    { "content": [{ "type": "text", "text": "valid" }, { "type": "text" }] },
    { "content": [{ "type": "image", "data": "aGk=" }] },
    { "content": [{ "type": "resource_link", "uri": "memo://1" }] },
    { "isError": false },
    { "content": [], "isError": "false" },
  ]
  for wire in invalid {
    match parse_call_tool(wire) {
      Err(@types.InvalidParams(_)) => ()
      Err(error) => raise error
      Ok(_) => fail("expected invalid tool content to fail")
    }
  }
}

///|
test "conformance: prompt content uses the same lossless codec" {
  let items : Array[Json] = [
    { "type": "audio", "data": "aGk=", "mimeType": "audio/wav", "_meta": {} },
    { "type": "resource", "resource": { "uri": "memo://1", "blob": "aGk=" } },
    { "type": "future", "extra": false },
  ]
  let messages = items.map(content => {
    Json::object({ "role": "assistant", "content": content })
  })
  match parse_get_prompt({ "messages": Json::array(messages) }) {
    Ok(result) => {
      assert_eq(result.messages.length(), 3)
      assert_eq(
        result.messages.map(message => message.content.to_json()),
        items,
      )
      for message in result.messages {
        assert_eq(message.role, "assistant")
      }
    }
    Err(error) => raise error
  }
}

///|
test "conformance: invalid prompt messages are not silently filtered" {
  let invalid : Array[Json] = [
    { "messages": [{ "role": "user", "content": { "type": "text" } }] },
    {
      "messages": [
        { "role": "system", "content": { "type": "text", "text": "t" } },
      ],
    },
    { "messages": [null] },
  ]
  for wire in invalid {
    match parse_get_prompt(wire) {
      Err(@types.InvalidParams(_)) => ()
      Err(error) => raise error
      Ok(_) => fail("expected invalid prompt message to fail")
    }
  }
}

///|
test "conformance: sampling serialization retains content metadata" {
  let content : Json = {
    "type": "audio",
    "data": "aGk=",
    "mimeType": "audio/wav",
    "annotations": { "audience": ["assistant"] },
    "_meta": { "com.example/key": null },
  }
  let result = @types.CreateMessageResult::new(
    @types.Role::Assistant,
    "test",
    @types.SamplingContent::from_json(content),
  )
  assert_eq(sampling_result_to_json(result), {
    "role": "assistant",
    "model": "test",
    "content": content,
  })
}
