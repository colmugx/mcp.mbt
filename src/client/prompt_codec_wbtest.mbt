///|
test "conformance: client prompt list and get retain all metadata" {
  let definition : Json = {
    "name": "greet",
    "title": "Greet",
    "icons": [],
    "_meta": {},
    "arguments": [{ "name": "name", "title": "Name", "required": false }],
  }
  {
    let result = parse_list_prompts({
      "prompts": [definition],
      "ttlMs": 0,
      "cacheScope": "private",
      "_meta": {},
      "com.example/top": null,
    })

    assert_eq(result.prompts[0].to_json(), definition)
    assert_eq(result.metadata.meta, Some(Map([])))
    assert_eq(result.metadata.extensions.get("com.example/top"), Some(null))
  }
  let wire : Json = {
    "messages": [
      {
        "role": "user",
        "content": { "type": "text", "text": "hello" },
        "com.example/key": false,
      },
    ],
    "_meta": {},
    "com.example/top": null,
  }
  {
    let result = parse_get_prompt(wire)
    assert_eq(result.to_json(), wire)
  }
  try
    parse_list_prompts({
      "prompts": [definition, { "name": "invalid", "arguments": [null] }],
    })
  catch {
    @types.InvalidParams(_) => ()
    error => raise error
  } noraise {
    _ => fail("expected malformed prompt list to fail")
  }
}
