///|
test "request builders reject malformed and non-object arguments" {
  for arguments in ["{\"text\":", "null", "[]", "42", "\"value\""] {
    try
      build_tools_call_request(1, "tool", Json::object({}), arguments~)
    catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("invalid tool arguments must not become an empty object")
    }
    try
      build_prompts_get_request(1, "prompt", Json::object({}), arguments~)
    catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("invalid prompt arguments must not become an empty object")
    }
  }
}

///|
test "tool progress metadata does not mutate caller metadata" {
  let meta : Json = { "protocolVersion": "2026-07-28" }
  let request = @json.parse(
    build_tools_call_request(
      1,
      "tool",
      meta,
      progress_token=@types.ProgressToken::String("progress"),
    ),
  )
  assert_eq(meta, ({ "protocolVersion": "2026-07-28" } : Json))
  guard request
    is {
      "params": { "_meta": { "progressToken": String("progress"), .. }, .. },
      ..
    } else {
    fail("request must include the progress token")
  }
}
