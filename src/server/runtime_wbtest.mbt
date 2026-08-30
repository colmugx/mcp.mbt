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
  assert_false(is_fast_method("tools/call"))
  assert_false(is_fast_method("resources/read"))
  assert_false(is_fast_method("prompts/get"))
}

///|
test "parse_request_message parse error responds without id member" {
  match parse_request_message("not json at all") {
    Ok(_) => panic()
    Err(response) => {
      let json = @json.parse(response) catch { _ => panic() }
      if json is Object(obj) {
        // JSON-RPC: id is null/absent on parse error; MCP forbids null,
        // so the member must be omitted (a fixed id like 0 would collide
        // with real id-0 requests).
        assert_true(obj.get("id") is None)
        match obj.get("error") {
          Some(Object(err)) =>
            match err.get("code") {
              Some(Number(n, ..)) => assert_eq(n.to_int(), -32700)
              _ => panic()
            }
          _ => panic()
        }
      } else {
        panic()
      }
    }
  }
}

///|
test "parse_request_message structural error responds without id member" {
  // Valid JSON, but no `method`: InvalidRequest (-32600), still no id.
  match parse_request_message("{\"jsonrpc\":\"2.0\",\"id\":0}") {
    Ok(_) => panic()
    Err(response) => {
      let json = @json.parse(response) catch { _ => panic() }
      if json is Object(obj) {
        assert_true(obj.get("id") is None)
        match obj.get("error") {
          Some(Object(err)) =>
            match err.get("code") {
              Some(Number(n, ..)) => assert_eq(n.to_int(), -32600)
              _ => panic()
            }
          _ => panic()
        }
      } else {
        panic()
      }
    }
  }
}

///|
test "check_protocol_version covers listen-style params without _meta" {
  // `subscriptions/listen` requests reach the same entry check via
  // handle_server_request; a filter payload without _meta is malformed.
  let params = Json::object({
    "notifications": Json::array([
      Json::string("notifications/tools/list_changed"),
    ]),
  })
  match check_protocol_version(@types.RequestId::Int(5), params) {
    Some(response) => {
      let json = @json.parse(response) catch { _ => panic() }
      let err = json_get(json, "error")
      match err {
        Object(err_obj) => {
          match err_obj.get("code") {
            Some(Number(n, ..)) => assert_eq(n.to_int(), -32602)
            _ => panic()
          }
          match err_obj.get("message") {
            Some(String(m)) =>
              assert_eq(
                m, "Missing required _meta field: io.modelcontextprotocol/protocolVersion",
              )
            _ => panic()
          }
        }
        _ => panic()
      }
      // The error echoes the request id when one is known.
      if json is Object(obj) {
        match obj.get("id") {
          Some(Number(n, ..)) => assert_eq(n.to_int(), 5)
          _ => panic()
        }
      } else {
        panic()
      }
    }
    None => panic()
  }
}
