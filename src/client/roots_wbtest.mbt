///|
test "MRTR roots checks request metadata and file URI responses" {
  let called = Ref(false)
  let client = MCPClient::MCPClient(
    name="test",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  ).on_roots(fn() {
    called.val = true
    Ok([{ uri: "https://example.org", name: None, }])
  })
  let requests : Map[String, (String, Json)] = {
    "roots": ("roots/list", { "_meta": false }),
  }
  assert_true(
    client.fulfill_input_requests(requests) is Err(@types.InvalidParams(_)),
  )
  assert_false(called.val)
  requests["roots"] = ("roots/list", {})
  assert_true(
    client.fulfill_input_requests(requests) is Err(@types.InvalidParams(_)),
  )
  assert_true(called.val)
}
