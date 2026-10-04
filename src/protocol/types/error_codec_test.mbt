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
    ] {
    let error = @types.MCPError::from_jsonrpc_error(wire)
    assert_eq(error.to_jsonrpc_error(), wire)
  }
}

///|
test "peer error codecs reject invalid or out of range codes without truncation" {
  for
    wire in [
      Json::object({ "code": 1.5, "message": "invalid" }),
      Json::object({ "code": 2147483648, "message": "invalid" }),
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
