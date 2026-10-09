///|
test "peer errors preserve code message data presence and unknown fields" {
  for
    wire in [
      Json::object({
        "code": -32602,
        "message": "unknown tool",
        "data": { "name": "missing" },
        "future": true,
      }),
      Json::object({ "code": 1001, "message": "custom", "data": null }),
      Json::object({ "code": -32000, "message": "custom" }),
      Json::object({ "code": 2147483648, "message": "custom" }),
      Json::object({
        "code": @types.JsonInteger::from_literal("9007199254740993").to_json(),
        "message": "custom",
        "data": null,
      }),
      Json::object({
        "code": @types.JsonInteger::from_literal("1e100000000000000000000").to_json(),
        "message": "custom",
      }),
    ] {
    let error = @types.MCPError::from_jsonrpc_error(wire)
    assert_eq(error.to_jsonrpc_error(), wire)
  }
}

///|
test "peer error codecs reject non-integer codes without truncation" {
  for
    wire in [
      Json::object({ "code": 1.5, "message": "invalid" }),
      Json::object({
        "code": Json::number(1, repr="1.00000000000000000001"),
        "message": "invalid",
      }),
      Json::object({ "code": "-32602", "message": "invalid" }),
      Json::object({ "message": "invalid" }),
    ] {
    try @types.MCPError::from_jsonrpc_error(wire) catch {
      @types.InvalidRequest(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("invalid error code must be rejected")
    }
  }
}
