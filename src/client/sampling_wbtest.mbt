///|
test "MRTR sampling tools require advertised nested support before dispatch" {
  let called = Ref(false)
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  ).on_sampling(fn(_) {
    called.val = true
    Ok(@types.CreateMessageResult::text("test", "done"))
  })
  let inputs : Map[String, (String, Json)] = Map::from_array([
    (
      "sampling",
      (
        "sampling/createMessage",
        Json::object({ "messages": [], "maxTokens": 1, "tools": [] }),
      ),
    ),
  ])
  assert_true(
    client.fulfill_input_requests(inputs)
    is Err(@types.MissingRequiredClientCapability(_, ..)),
  )
  assert_false(called.val)
  let enabled = client.with_capabilities(
    @types.ClientCapabilities::new(
      sampling=@types.SamplingCapabilities::new(tools=Map([])),
    ),
  )
  assert_eq(
    enabled.fulfill_input_requests(inputs).unwrap().get("sampling"),
    Some(@types.CreateMessageResult::text("test", "done").to_json()),
  )
  assert_true(called.val)
  called.val = false
  let choice : Map[String, (String, Json)] = Map::from_array([
    (
      "sampling",
      (
        "sampling/createMessage",
        Json::object({ "messages": [], "maxTokens": 1, "toolChoice": {} }),
      ),
    ),
  ])
  assert_true(
    client.fulfill_input_requests(choice)
    is Err(@types.MissingRequiredClientCapability(_, ..)),
  )
  assert_false(called.val)
}

///|
test "MRTR sampling rejects malformed requests before invoking the handler" {
  let called = Ref(false)
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  ).on_sampling(fn(_) {
    called.val = true
    Ok(@types.CreateMessageResult::text("test", "done"))
  })
  let inputs : Map[String, (String, Json)] = Map::from_array([
    (
      "sampling",
      (
        "sampling/createMessage",
        Json::object({ "messages": [], "maxTokens": "1" }),
      ),
    ),
  ])
  assert_true(
    client.fulfill_input_requests(inputs) is Err(@types.InvalidParams(_)),
  )
  assert_false(called.val)
}

///|
test "MRTR sampling validates handler results before serializing input responses" {
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  ).on_sampling(fn(_) {
    Ok(
      @types.CreateMessageResult::new(
        @types.Role::Assistant,
        "test",
        @types.SamplingContent::Single(
          @types.SamplingContentBlock::Unknown(Json::object({ "type": "text" })),
        ),
      ),
    )
  })
  let inputs : Map[String, (String, Json)] = Map::from_array([
    (
      "sampling",
      (
        "sampling/createMessage",
        Json::object({ "messages": [], "maxTokens": 1 }),
      ),
    ),
  ])
  assert_true(
    client.fulfill_input_requests(inputs) is Err(@types.InvalidParams(_)),
  )
}
