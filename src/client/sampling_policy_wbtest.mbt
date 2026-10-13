///|
test "MRTR sampling rejects handler output that violates required tool choice" {
  let client = MCPClient::MCPClient(
      name="test",
      version="1",
      transport=@transport.AnyTransport::Stdio(
        @transport.StdioTransport::StdioTransport(),
      ),
    )
    .on_sampling(fn(_) { Ok(@types.CreateMessageResult::text("model", "done")) })
    .with_capabilities(
      @types.ClientCapabilities::new(
        sampling=@types.SamplingCapabilities::new(tools=Map([])),
      ),
    )
  let inputs : Map[String, (String, Json)] = Map::from_array([
    (
      "sampling",
      (
        "sampling/createMessage",
        { "messages": [], "maxTokens": 1, "toolChoice": { "mode": "required" } },
      ),
    ),
  ])
  assert_true(
    client.fulfill_input_requests(inputs) is Err(@types.InvalidParams(_)),
  )
}
