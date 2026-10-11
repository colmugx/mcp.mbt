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
  let exact = @types.ProgressToken::ExactNumber(
    @types.JsonNumber::from_literal("9007199254740993"),
  )
  let wire = @validation.parse_json(
    build_tools_call_request(2, "tool", meta, progress_token=exact),
  )
  guard wire
    is { "params": { "_meta": { "progressToken": token, .. }, .. }, .. } else {
    fail("request must retain the progress token")
  }
  assert_eq(token.stringify(), "9007199254740993")
  assert_eq(@types.ProgressToken::from_json(token), exact)
  guard build_legacy_meta(progress_token=exact)
    is { "progressToken": token, .. } else {
    fail("legacy metadata must retain the progress token")
  }
  assert_eq(token.stringify(), "9007199254740993")
}

///|
test "progress notification dispatch accepts numeric tokens without integer coercion" {
  let parsed = parse_progress_notification({
    "progressToken": 7.5,
    "progress": 2,
    "total": 5,
  }).unwrap()
  assert_eq(parsed.progress_token, @types.ProgressToken::Number(7.5))
  let received : Array[@types.ProgressToken] = []
  let handlers = {
    ..NotificationHandlers::empty(),
    on_progress: Some(notification => received.push(notification.progress_token)),
  }
  for literal in ["9007199254740992", "9007199254740993"] {
    handle_server_notification(handlers, {
      method_name: "notifications/progress",
      params: Some(
        @validation.parse_json("{\"progressToken\":\{literal},\"progress\":1}"),
      ),
    })
  }
  assert_eq(received.length(), 2)
  assert_true(received[0] != received[1])
  assert_eq(received[1].to_json().stringify(), "9007199254740993")
  assert_eq(
    parse_progress_notification({ "progressToken": true, "progress": 2 }),
    None,
  )
}
