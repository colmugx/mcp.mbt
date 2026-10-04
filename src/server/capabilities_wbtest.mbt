///|
fn capability_test_params(capabilities : Json) -> Json {
  { "_meta": { "io.modelcontextprotocol/clientCapabilities": capabilities } }
}

///|
test "MRTR checks elicitation mode rather than only the top-level capability key" {
  let requests : Map[String, @types.InputRequestEntry] = Map::from_array([
    (
      "input",
      {
        method_name: @types.ElicitationCreate,
        params: {
          "mode": "url",
          "message": "authorize",
          "url": "https://example.org",
          "elicitationId": "auth",
        },
      },
    ),
  ])
  assert_true(
    check_required_capabilities(
      capability_test_params({ "elicitation": { "form": {} } }),
      requests,
    )
    is Some(@types.MissingRequiredClientCapability(_, ..)),
  )
  assert_eq(
    check_required_capabilities(
      capability_test_params({ "elicitation": { "url": {} } }),
      requests,
    ),
    None,
  )
  requests.set("input", {
    method_name: @types.ElicitationCreate,
    params: { "message": "name", "requestedSchema": { "type": "object" } },
  })
  assert_eq(
    check_required_capabilities(
      capability_test_params({ "elicitation": {} }),
      requests,
    ),
    None,
  )
  assert_true(
    check_required_capabilities(
      capability_test_params({ "elicitation": { "url": {} } }),
      requests,
    )
    is Some(@types.MissingRequiredClientCapability(_, ..)),
  )
}

///|
test "MRTR sampling tools requires the nested tools capability" {
  let requests : Map[String, @types.InputRequestEntry] = Map::from_array([
    (
      "sample",
      {
        method_name: @types.SamplingCreateMessage,
        params: { "tools": [], "maxTokens": 1, "messages": [] },
      },
    ),
  ])
  match
    check_required_capabilities(
      capability_test_params({ "sampling": {} }),
      requests,
    ) {
    Some(error) =>
      assert_eq(
        error.to_error_data(),
        Some(
          Json::object({
            "requiredCapabilities": { "sampling": { "tools": {} } },
          }),
        ),
      )
    None => fail("sampling.tools is required")
  }
  assert_eq(
    check_required_capabilities(
      capability_test_params({ "sampling": { "tools": {} } }),
      requests,
    ),
    None,
  )
}

///|
test "request metadata validates nested client capability fields" {
  let params : Json = {
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": @types.ProtocolVersion,
      "io.modelcontextprotocol/clientCapabilities": {
        "elicitation": { "form": true },
      },
    },
  }
  let error = check_protocol_version(@types.RequestId::Int(1), params).unwrap()
  guard @json.parse(error)
    is { "error": { "code": Number(-32602, ..), .. }, .. } else {
    fail("malformed capability must be InvalidParams")
  }
}
