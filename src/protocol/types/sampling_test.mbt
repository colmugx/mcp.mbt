///|
test "sampling request round trips model preferences tool choice and open fields" {
  let wire : Json = {
    "messages": [
      {
        "role": "user",
        "content": [
          { "type": "text", "text": "inspect", "_meta": {} },
          { "type": "audio", "data": "aGk=", "mimeType": "audio/wav" },
        ],
        "_meta": { "trace": "1" },
        "future": false,
      },
    ],
    "maxTokens": 1024.5,
    "modelPreferences": {
      "hints": [{ "name": "model", "future": null }, {}],
      "costPriority": 0,
      "speedPriority": 1,
      "intelligencePriority": 0.5,
      "future": [],
    },
    "includeContext": "allServers",
    "systemPrompt": "",
    "temperature": 0,
    "stopSequences": [],
    "metadata": {},
    "tools": [
      {
        "name": "inspect",
        "inputSchema": { "type": "object" },
        "outputSchema": { "type": "object" },
        "_meta": {},
      },
    ],
    "toolChoice": { "mode": "required", "future": true },
    "future": null,
  }
  assert_eq(@types.CreateMessageRequest::from_json(wire).to_json(), wire)
}

///|
test "sampling preserves single and array content and tool interaction blocks" {
  let tool_use : Json = {
    "type": "tool_use",
    "id": "u1",
    "name": "inspect",
    "input": { "name": "x" },
    "_meta": {},
    "future": [],
  }
  let result : Json = {
    "type": "tool_result",
    "toolUseId": "u1",
    "content": [
      { "type": "resource", "resource": { "uri": "memo://1", "blob": "aGk=" } },
    ],
    "structuredContent": null,
    "isError": false,
    "_meta": { "trace": 1 },
    "future": null,
  }
  for
    content in [
      tool_use,
      Json::array([tool_use]),
      Json::array([tool_use, result]),
      Json::array([]),
      Json::object({ "type": "future", "payload": {} }),
    ] {
    let wire : Json = {
      "role": "assistant",
      "model": "test",
      "content": content,
      "stopReason": "futureReason",
      "_meta": {},
      "future": false,
    }
    assert_eq(@types.CreateMessageResult::from_json(wire).to_json(), wire)
  }
  assert_eq(@types.CreateMessageResult::text("test", "done").to_json(), {
    "role": "assistant",
    "model": "test",
    "content": { "type": "text", "text": "done" },
  })
}

///|
test "sampling omitted preferences remain absent and none tool choice uses a typed enum" {
  let wire : Json = { "messages": [], "maxTokens": 1 }
  assert_eq(@types.CreateMessageRequest::from_json(wire).to_json(), wire)
  assert_eq(@types.ToolChoice::from_json({}).to_json(), {})
  let choice = @types.ToolChoice::from_json({ "mode": "none" })
  assert_eq(choice.mode, Some(@types.ToolChoiceMode::Disabled))
  assert_eq(choice.to_json(), { "mode": "none" })
}

///|
test "sampling rejects malformed known fields instead of filtering messages or tools" {
  for
    wire in [
      Json::object({ "messages": [], "maxTokens": "10" }),
      Json::object({
        "messages": [
          { "role": "system", "content": { "type": "text", "text": "x" } },
        ],
        "maxTokens": 1,
      }),
      Json::object({
        "messages": [{ "role": "user", "content": [{ "type": "text" }] }],
        "maxTokens": 1,
      }),
      Json::object({
        "messages": [],
        "maxTokens": 1,
        "modelPreferences": { "costPriority": 1.01 },
      }),
      Json::object({
        "messages": [],
        "maxTokens": 1,
        "modelPreferences": { "speedPriority": -0.01 },
      }),
      Json::object({
        "messages": [],
        "maxTokens": 1,
        "includeContext": "future",
      }),
      Json::object({ "messages": [], "maxTokens": 1, "stopSequences": [1] }),
      Json::object({ "messages": [], "maxTokens": 1, "metadata": null }),
      Json::object({
        "messages": [],
        "maxTokens": 1,
        "tools": [{ "name": "invalid", "inputSchema": {} }],
      }),
      Json::object({
        "messages": [],
        "maxTokens": 1,
        "toolChoice": { "mode": "future" },
      }),
    ] {
    try @types.CreateMessageRequest::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("malformed sampling request must be rejected")
    }
  }
}

///|
test "sampling rejects malformed tool blocks and top level resource content" {
  for
    content in [
      Json::object({
        "type": "tool_use",
        "id": "u1",
        "name": "inspect",
        "input": null,
      }),
      Json::object({ "type": "tool_use", "name": "inspect", "input": {} }),
      Json::object({ "type": "tool_result", "toolUseId": "u1", "content": null }),
      Json::object({
        "type": "tool_result",
        "toolUseId": "u1",
        "content": [{ "type": "text" }],
      }),
      Json::object({
        "type": "resource",
        "resource": { "uri": "memo://1", "text": "x" },
      }),
      Json::object({
        "type": "resource_link",
        "uri": "memo://1",
        "name": "memo",
      }),
    ] {
    try @types.SamplingContent::from_json(content) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("malformed sampling block must be rejected")
    }
  }
}
