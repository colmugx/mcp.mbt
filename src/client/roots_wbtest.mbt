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
  try client.fulfill_input_requests(requests) catch {
    @types.InvalidParams(_) => ()
    error => raise error
  } noraise {
    _ => fail("expected protocol error")
  }
  assert_false(called.val)
  requests["roots"] = ("roots/list", {})
  try client.fulfill_input_requests(requests) catch {
    @types.InvalidParams(_) => ()
    error => raise error
  } noraise {
    _ => fail("expected protocol error")
  }
  assert_true(called.val)
}
