///|
test "MRTR elicitation uses the shared enum codec and never serializes absent content as null" {
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  ).on_elicitation(fn(_) {
    Ok(@types.ElicitationResult::new(@types.ElicitationAction::Cancel))
  })
  let inputs : Map[String, (String, Json)] = Map::from_array([
    (
      "form",
      (
        "elicitation/create",
        Json::object({
          "message": "name",
          "requestedSchema": { "type": "object", "properties": {} },
        }),
      ),
    ),
  ])
  let response = client.fulfill_input_requests(inputs).unwrap()
  assert_eq(response.get("form"), Some(Json::object({ "action": "cancel" })))
}

///|
test "MRTR URL elicitation is not dispatched to a form-only client handler" {
  let called = Ref(false)
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  ).on_elicitation(fn(_) {
    called.val = true
    Ok(@types.ElicitationResult::new(@types.ElicitationAction::Accept))
  })
  let inputs : Map[String, (String, Json)] = Map::from_array([
    (
      "url",
      (
        "elicitation/create",
        Json::object({
          "mode": "url",
          "message": "authorize",
          "url": "https://example.org",
          "elicitationId": "id",
        }),
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
      elicitation=@types.ElicitationCapabilities::new(form=Map([]), url=Map([])),
    ),
  )
  assert_true(enabled.fulfill_input_requests(inputs) is Ok(_))
  assert_true(called.val)
}

///|
test "MRTR elicitation rejects unsupported form constraints before invoking user code" {
  let called = Ref(false)
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  ).on_elicitation(fn(_) {
    called.val = true
    Ok(@types.ElicitationResult::new(@types.Cancel))
  })
  let inputs : Map[String, (String, Json)] = {
    "input": (
      "elicitation/create",
      {
        "message": "name",
        "requestedSchema": {
          "type": "object",
          "properties": { "name": { "type": "string", "$dynamicRef": "#name" } },
        },
      },
    ),
  }
  assert_true(
    client.fulfill_input_requests(inputs) is Err(@types.InvalidParams(_)),
  )
  assert_false(called.val)
}

///|
test "MRTR elicitation validates returned form data using the pre-handler snapshot" {
  let properties : Map[String, Json] = {
    "age": { "type": "integer", "minimum": 18 },
  }
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  ).on_elicitation(fn(_) {
    properties["age"] = { "type": "integer" }
    Ok(
      @types.ElicitationResult::new(@types.Accept, content={
        "age": @types.ElicitationValue::Number(17),
      }),
    )
  })
  let inputs : Map[String, (String, Json)] = {
    "input": (
      "elicitation/create",
      {
        "message": "age",
        "requestedSchema": {
          "type": "object",
          "properties": Json::object(properties),
          "required": ["age"],
        },
      },
    ),
  }
  assert_true(
    client.fulfill_input_requests(inputs) is Err(@types.InvalidParams(_)),
  )
}
