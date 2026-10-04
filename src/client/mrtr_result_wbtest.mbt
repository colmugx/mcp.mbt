///|
test "MRTR rejects malformed input_required fields without silently dropping entries" {
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  )
  for
    result in [
      Json::object({ "resultType": "input_required" }),
      Json::object({ "resultType": "input_required", "requestState": null }),
      Json::object({ "resultType": "input_required", "requestState": 1 }),
      Json::object({
        "resultType": "input_required",
        "requestState": "blob",
        "inputRequests": [],
      }),
      Json::object({
        "resultType": "input_required",
        "inputRequests": { "a": null },
      }),
      Json::object({
        "resultType": "input_required",
        "inputRequests": { "a": {} },
      }),
      Json::object({
        "resultType": "input_required",
        "inputRequests": { "a": { "method": "roots/list", "params": null } },
      }),
      Json::object({
        "resultType": "input_required",
        "inputRequests": { "a": { "method": "sampling/createMessage" } },
      }),
      Json::object({
        "resultType": "input_required",
        "inputRequests": {
          "valid": { "method": "roots/list" },
          "invalid": false,
        },
      }),
    ] {
    let response = Json::object({ "jsonrpc": "2.0", "id": 1, "result": result }).stringify()
    assert_true(
      client.check_input_required(response) is Err(@types.InvalidParams(_)),
    )
  }
}

///|
test "MRTR accepts state-only load shedding and roots requests without params" {
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  )
  let state = client
    .check_input_required(
      Json::object({
        "result": { "resultType": "input_required", "requestState": "opaque" },
      }).stringify(),
    )
    .unwrap()
    .unwrap()
  assert_eq(state.request_state, Some("opaque"))
  assert_true(state.input_requests.is_empty())
  let roots = client
    .check_input_required(
      Json::object({
        "result": {
          "resultType": "input_required",
          "inputRequests": { "roots": { "method": "roots/list" } },
        },
      }).stringify(),
    )
    .unwrap()
    .unwrap()
  assert_eq(roots.request_state, None)
  assert_eq(
    roots.input_requests.get("roots"),
    Some(("roots/list", Json::object({}))),
  )
  let empty = client
    .check_input_required(
      Json::object({
        "result": { "resultType": "input_required", "inputRequests": {} },
      }).stringify(),
    )
    .unwrap()
    .unwrap()
  assert_true(empty.input_requests.is_empty())
}
