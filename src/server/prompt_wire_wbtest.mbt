///|
async test "conformance: prompt registration preserves title icons arguments metadata and message extensions" {
  let definition = @types.PromptDefinition::from_json({
    "name": "greet",
    "title": "Greet",
    "icons": [],
    "_meta": {},
    "arguments": [{ "name": "name", "title": "Name", "required": false }],
    "annotations": { "com.example/hint": false },
  })
  let result = @types.GetPromptResult::from_json({
    "messages": [
      {
        "role": "user",
        "content": { "type": "text", "text": "hello" },
        "com.example/message": null,
      },
    ],
    "_meta": { "com.example/result": false },
    "com.example/top": [],
  })
  let server = MCPServer::MCPServer("test", "1").prompt_definition(definition, (
    _context,
    _,
  ) => Ok(@prompt.PromptGetOutcome::Complete(result)))
  let listed = @json.parse(
    handle_prompts_list(server, @types.RequestId::Int(1)),
  )
  guard listed is { "result": { "prompts": Array(prompts), .. }, .. } else {
    fail("expected prompt list")
  }
  assert_eq(prompts, [definition.to_json()])
  let completed = @json.parse(
    handle_prompts_get(
      server,
      @runtime.RequestContext::new(@types.RequestId::Int(2)),
      { "name": "greet", "arguments": {} },
    ),
  )
  guard completed is { "result": Object(fields), .. } else {
    fail("expected prompt result")
  }
  let decoded = @types.GetPromptResult::from_json(Json::object(fields))
  assert_eq(decoded.messages, result.messages)
  assert_eq(
    decoded.metadata.meta.unwrap().get("com.example/result"),
    Some(false),
  )
  assert_eq(decoded.metadata.extensions.get("com.example/top"), Some([]))
  assert_eq(result.metadata.server_info(), None)
}
