///|
test "HTTP status mappings distinguish protocol errors from application errors" {
  for
    entry in [
      (-32020, 400),
      (-32021, 400),
      (-32022, 400),
      (-32601, 404),
      (-32602, 200),
      (-32603, 200),
      (-32099, 200),
    ] {
    let (code, expected) = entry
    let message = (
      {
        "jsonrpc": "2.0",
        "id": 1,
        "error": { "code": Json::number(code.to_double()), "message": "test" },
      } : Json).stringify()
    let (status, _) = http_response_status(message)
    assert_eq(status, expected)
  }
}
