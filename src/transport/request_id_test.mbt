///|
test "transport errors echo exact valid ids and omit invalid ids" {
  for
    literal in [
      "9007199254740993", "1e100000000000000000000", "\"9007199254740993\"", "4.2e1",
    ] {
    let body = "{\"jsonrpc\":\"2.0\",\"id\":" +
      literal +
      ",\"method\":\"tools/list\"}"
    let id = @transport.request_id_from_body(body).unwrap()
    assert_eq(@types.RequestId::from_json(id).to_json_string(), literal)
    let error = @validation.parse_json(
      @transport.header_mismatch_error("mismatch", body~),
    )
    guard error is Object(fields) && fields.get("id") is Some(echoed) else {
      fail("missing valid id")
    }
    assert_eq(@types.RequestId::from_json(echoed).to_json_string(), literal)
  }
  for literal in ["null", "true", "{}", "42.1", "42.00000000000000000001"] {
    let body = "{\"id\":" + literal + "}"
    assert_eq(@transport.request_id_from_body(body), None)
    let error = @validation.parse_json(
      @transport.invalid_params_error("invalid", body~),
    )
    guard error is Object(fields) else { fail("expected response") }
    assert_false(fields.contains("id"))
  }
  for code in ["4294934695", "-32601.00000000000000000001", "1e1000"] {
    assert_eq(
      @transport.jsonrpc_error_code("{\"error\":{\"code\":" + code + "}}"),
      None,
    )
  }
  assert_eq(
    @transport.jsonrpc_error_code("{\"error\":{\"code\":-32601.0}}"),
    Some(-32601),
  )
}
