///|
test "HTTP stream ownership rejects independent requests and mismatched responses" {
  let expected = Some(@validation.parse_json("9007199254740993"))
  assert_eq(
    check_http_response(
      "{\"jsonrpc\":\"2.0\",\"id\":9007199254740993,\"result\":{}}", expected,
    ),
    FinalResponse,
  )
  for
    message in [
      "{\"jsonrpc\":\"2.0\",\"id\":9007199254740992,\"result\":{}}", "{\"jsonrpc\":\"2.0\",\"id\":\"9007199254740993\",\"result\":{}}",
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"sampling/createMessage\",\"params\":{}}",
      "{\"jsonrpc\":\"2.0\",\"id\":9007199254740993,\"result\":{},\"error\":{}}",
    ] {
    try check_http_response(message, expected) catch {
      @types.ReadError(_) => ()
      error => raise error
    } noraise {
      _ => fail("invalid HTTP response accepted")
    }
  }
}
