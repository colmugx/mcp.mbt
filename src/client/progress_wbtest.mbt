///|
test "tool and legacy request metadata preserve numeric and empty string progress tokens" {
  let meta = test_meta()
  let request = @json.parse(
    build_tools_call_request(
      1,
      "tool",
      meta,
      progress_token=@types.ProgressToken::Number(7.5),
    ),
  )
  guard request
    is {
      "params": { "_meta": { "progressToken": Number(7.5, ..), .. }, .. },
      ..
    } else {
    fail("numeric progress token must remain numeric")
  }
  assert_eq(
    build_legacy_meta(progress_token=@types.ProgressToken::String("")),
    Json::object({ "progressToken": "" }),
  )
  assert_eq(
    build_legacy_meta(progress_token=@types.ProgressToken::Number(7.5)),
    Json::object({ "progressToken": 7.5 }),
  )
}

///|
test "progress notification dispatch accepts numeric tokens without integer coercion" {
  let parsed = parse_progress_notification({
    "progressToken": 7.5,
    "progress": 2,
    "total": 5,
  }).unwrap()
  assert_eq(parsed.progress_token, @types.ProgressToken::Number(7.5))
  assert_eq(
    parse_progress_notification({ "progressToken": true, "progress": 2 }),
    None,
  )
}
