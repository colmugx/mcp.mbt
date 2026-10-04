///|
test "progress tokens round trip strings and fractional numeric identifiers" {
  for
    value in [
      Json::string(""),
      Json::string("token"),
      Json::number(0),
      Json::number(1234567890123.5),
    ] {
    assert_eq(@types.ProgressToken::from_json(value).to_json(), value)
  }
  let wire : Json = {
    "progressToken": 7.5,
    "progress": 1,
    "total": 10,
    "message": "working",
    "future": { "phase": 2 },
  }
  assert_eq(@types.ProgressNotification::from_json(wire).to_json(), wire)
  let notification = @types.progress_notification(
    @types.ProgressToken::Number(7.5),
    1,
    total=10,
    message="working",
  )
  assert_eq(
    notification.params,
    Some(
      Json::object({
        "progressToken": 7.5,
        "progress": 1,
        "total": 10,
        "message": "working",
      }),
    ),
  )
}

///|
test "progress codecs reject malformed tokens numbers and optional fields" {
  for
    wire in [
      Json::object({ "progressToken": null, "progress": 1 }),
      Json::object({ "progressToken": false, "progress": 1 }),
      Json::object({ "progressToken": "p", "progress": "1" }),
      Json::object({ "progressToken": "p", "progress": 1, "total": null }),
      Json::object({ "progressToken": "p", "progress": 1, "message": false }),
    ] {
    try @types.ProgressNotification::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("malformed progress notification must be rejected")
    }
  }
}
