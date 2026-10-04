///|
test "explicit input capabilities require matching registered handlers" {
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  )
  for
    capabilities in [
      @types.ClientCapabilities::new(roots=@types.RootCapabilities::new()),
      @types.ClientCapabilities::new(
        sampling=@types.SamplingCapabilities::new(),
      ),
      @types.ClientCapabilities::new(
        elicitation=@types.ElicitationCapabilities::new(url=Map([])),
      ),
    ] {
    try client.with_capabilities(capabilities) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("advertised capability requires its handler")
    }
  }
}

///|
test "explicit configuration preserves extension settings and can disable registered input handlers" {
  let called = Ref(false)
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  ).on_roots(fn() {
    called.val = true
    Ok([])
  })
  let configured = client.with_capabilities(
    @types.ClientCapabilities::new(experimental={ "feature": {} }, extensions={
      "example.org/extension": { "version": 2 },
    }),
  )
  assert_eq(configured.capabilities.to_json(), {
    "experimental": { "feature": {} },
    "extensions": { "example.org/extension": { "version": 2 } },
  })
  let inputs : Map[String, (String, Json)] = Map::from_array([
    ("roots", ("roots/list", Json::object({}))),
  ])
  assert_true(
    configured.fulfill_input_requests(inputs)
    is Err(@types.MissingRequiredClientCapability(_, ..)),
  )
  assert_false(called.val)
}

///|
test "elicitation handler registration advertises explicitly enabled URL mode" {
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  ).on_elicitation(
    fn(_) {
      Ok(@types.ElicitationResult::new(@types.ElicitationAction::Cancel))
    },
    capabilities=@types.ElicitationCapabilities::new(form=Map([]), url=Map([])),
  )
  assert_eq(client.capabilities.to_json(), {
    "elicitation": { "form": {}, "url": {} },
  })
}
