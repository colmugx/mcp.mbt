///|
fn sampling_history(messages : Json) -> Json {
  { "messages": messages, "maxTokens": 10 }
}

///|
test "sampling histories require complete adjacent tool exchanges" {
  let use_a : Json = { "type": "tool_use", "id": "a", "name": "f", "input": {} }
  let use_b : Json = { "type": "tool_use", "id": "b", "name": "f", "input": {} }
  let result_a : Json = {
    "type": "tool_result",
    "toolUseId": "a",
    "content": [],
  }
  let result_b : Json = {
    "type": "tool_result",
    "toolUseId": "b",
    "content": [],
  }
  let text : Json = { "type": "text", "text": "next" }
  let assistant : Json = { "role": "assistant", "content": [use_a, use_b] }
  let user : Json = { "role": "user", "content": [result_b, result_a] }
  for
    valid in [
      ([assistant, user] : Json),
      [
        { "role": "assistant", "content": use_a },
        { "role": "user", "content": result_a },
      ],
      [assistant, user, { "role": "user", "content": text }, assistant, user],
    ] {
    ignore(@validation.check_sampling_request(sampling_history(valid)))
  }
  for
    invalid in [
      ([assistant] : Json),
      [assistant, { "role": "user", "content": result_a }],
      [assistant, { "role": "user", "content": [result_a, result_a] }],
      [assistant, { "role": "user", "content": [result_a, result_b, text] }],
      [assistant, { "role": "assistant", "content": [result_a, result_b] }],
      [{ "role": "user", "content": use_a }],
      [user],
      [assistant, { "role": "user", "content": text }, user],
      [{ "role": "assistant", "content": [use_a, use_a] }, user],
      [
        { "role": "assistant", "content": use_a },
        { "role": "user", "content": result_b },
      ],
    ] {
    try @validation.check_sampling_request(sampling_history(invalid)) catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("invalid sampling history accepted: " + invalid.stringify())
    }
  }
}
