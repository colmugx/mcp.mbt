///|
test "client advertises only registered input handlers by default" {
  let client = MCPClient::MCPClient(
    name="test",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  )
  assert_eq(client.capabilities.to_json(), Json::object({}))
  let client = client
    .on_roots(fn() { Ok([]) })
    .on_sampling(fn(_) { Err(@types.InternalError("not executed")) })
    .on_elicitation(fn(_) { Err(@types.InternalError("not executed")) })
  assert_eq(
    client.capabilities.to_json(),
    Json::object({ "roots": {}, "sampling": {}, "elicitation": { "form": {} } }),
  )
  assert_eq(
    client_capabilities_to_json(client.capabilities),
    client.capabilities.to_json(),
  )
}

///|
test "discovery parser retains completion support and rejects malformed flags" {
  let wire : Json = {
    "capabilities": {
      "completions": {},
      "logging": {},
      "tools": { "listChanged": false },
      "future": { "revision": 2 },
    },
  }
  let value = parse_discover_capabilities(wire)
  assert_eq(value.to_json(), {
    "completions": {},
    "logging": {},
    "tools": { "listChanged": false },
    "future": { "revision": 2 },
  })
  try
    parse_discover_capabilities({
      "capabilities": { "tools": { "listChanged": "yes" } },
    })
  catch {
    @types.InvalidParams(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("discovery must reject malformed capability fields")
  }
}
