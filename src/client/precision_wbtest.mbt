///|
test "tool wire values keep exact decimal literals through build, retry and response decode" {
  let literal = "0.30000000000000000000000000000000000001"
  let meta : Json = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
  }
  let request = build_tools_call_request(
    1,
    "precise",
    meta,
    arguments="{\"amount\":" + literal + "}",
  )
  let retry = build_retry_request(request, 2, Map([]), Some("opaque"))
  let legacy = apply_legacy_meta_to_request(request, {})
  for wire in [request, retry, legacy] {
    let parsed = @validation.parse_json(wire)
    guard parsed
      is { "params": { "arguments": { "amount": amount, .. }, .. }, .. } else {
      fail("arguments missing")
    }
    assert_eq(amount.stringify(), literal)
  }
  let wire = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"content\":[],\"structuredContent\":" +
    literal +
    ",\"isError\":false,\"resultType\":\"complete\"}}"
  match parse_jsonrpc_response(wire) {
    Ok(result) => {
      let parsed = parse_call_tool(result)
      match parsed {
        Ok(result) =>
          assert_eq(result.structured_content.unwrap().stringify(), literal)
        Err(error) => raise error
      }
    }
    Err(error) => raise error
  }
}
