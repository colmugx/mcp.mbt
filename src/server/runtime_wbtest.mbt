///| Server runtime white-box tests

///|
test "parse_request_message accepts formatted JSON-RPC requests" {
  let message = "{\n  \"jsonrpc\": \"2.0\",\n  \"id\": 1,\n  \"method\": \"tools/list\"\n}"
  match parse_request_message(message) {
    Ok(request) => {
      assert_true(request.method_name == "tools/list")
      assert_true(is_fast_method(request.method_name))
    }
    Err(_) => panic()
  }
}

///|
test "is_fast_method distinguishes concurrent handlers" {
  assert_true(is_fast_method("tools/list"))
  assert_true(is_fast_method("resources/list"))
  assert_true(is_fast_method("prompts/list"))
  assert_true(!is_fast_method("tools/call"))
  assert_true(!is_fast_method("resources/read"))
  assert_true(!is_fast_method("prompts/get"))
}
