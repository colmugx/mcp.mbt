///|
test "requestState timestamps reject narrowing and expiry skew does not overflow" {
  for literal in ["1700000000.5", "2147483648", "4294967296"] {
    let value = @validation.parse_json("{\"expires_at\":\{literal}}")
    assert_eq(get_number_field(value, "expires_at"), None)
  }
  assert_eq(
    get_number_field(
      @validation.parse_json("{\"expires_at\":1.7e9}"),
      "expires_at",
    ),
    Some(1700000000),
  )
  let codec = AesGcmStateCodec::with_key(fixed_key())
  let params = Json::object({})
  let payload : RequestStatePayload = {
    principal: None,
    expires_at: 2147483647,
    request_method: "tools/call",
    params_digest: params_digest(params),
    state: Json::null(),
  }
  let context : RequestStateContext = {
    principal: None,
    request_method: "tools/call",
    params,
  }
  let blob = codec.seal(payload, now=2147483646)
  assert_true(codec.open(blob, context, now=2147483647) is Some(_))
}
