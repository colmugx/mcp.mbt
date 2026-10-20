///|
async test "subscriptions reject malformed filters and duplicate ids without replacing a stream" {
  let server = MCPServer::MCPServer("test", "1").with_tools()
  let original : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  let request : @types.JsonRpcRequest = {
    jsonrpc: "2.0",
    id: @types.RequestId::Int(5),
    method_name: "subscriptions/listen",
    params: { "notifications": { "toolsListChanged": true } },
  }
  server.handle_subscriptions_listen(request, original)
  let duplicate : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  server.handle_subscriptions_listen(request, duplicate)
  assert_true(
    @validation.parse_json(duplicate.get())
    is { "error": { "code": -32600, .. }, .. },
  )
  server.notify_tools_list_changed()
  assert_true(
    @validation.parse_json(original.get())
    is { "method": "notifications/subscriptions/acknowledged", .. },
  )
  assert_true(
    @validation.parse_json(original.get())
    is { "method": "notifications/tools/list_changed", .. },
  )
  for
    params in [
      ({} : Json),
      { "notifications": null },
      { "notifications": { "toolsListChanged": 1 } },
      { "notifications": { "resourceSubscriptions": ["file:///ok", 1] } },
    ] {
    let reply : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
    server.handle_subscriptions_listen(
      { ..request, id: @types.RequestId::Int(6), params, },
      reply,
    )
    assert_true(
      @validation.parse_json(reply.get())
      is { "error": { "code": -32602, .. }, .. },
    )
    assert_false(server.subscriptions.contains(@types.RequestId::Int(6).key()))
  }
}
