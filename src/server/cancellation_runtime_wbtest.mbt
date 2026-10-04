///|
async test "cancellation stops the handler and is isolated by transport scope" {
  let started : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  let stopped : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  let replies_a : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  let replies_b : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  let server = MCPServer::MCPServer("test", "1").tool(
    "slow",
    "Slow",
    { "type": "object" },
    (context, _) => {
      let peer = context.principal.map(fn(p) { p.id }).unwrap()
      defer ignore(stopped.try_put(peer) catch { _ => false })
      started.put(peer)
      @async.sleep(10000)
      Ok(@tool.ToolResult::text("must not be emitted"))
    },
  )
  @async.with_task_group(group => {
    server.handle_server_request(
      { message: runtime_request(7, "slow", {}), reply: replies_a, },
      group,
      scope="peer-a",
      principal=@runtime.Principal::new("a"),
    )
    server.handle_server_request(
      { message: runtime_request(7, "slow", {}), reply: replies_b, },
      group,
      scope="peer-b",
      principal=@runtime.Principal::new("b"),
    )
    ignore(started.get())
    ignore(started.get())
    let notification = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":7}}"
    server.handle_inbound_notification(notification, scope="unrelated")
    assert_eq(server.active_requests.length(), 2)
    server.handle_inbound_notification(notification, scope="peer-a")
    assert_eq(stopped.get(), "a")
    assert_true(replies_a.try_get() is None)
    assert_true(
      server.active_requests.contains(scoped_request_key("peer-b", "7")),
    )
    assert_true(replies_b.try_get() is None)
    server.handle_inbound_notification(notification, scope="peer-b")
    assert_eq(stopped.get(), "b")
  })
  assert_true(server.active_requests.is_empty())
  assert_true(replies_a.try_get() is None)
  assert_true(replies_b.try_get() is None)
}

///|
async test "cancelled handler cannot emit a late result even if it handles task cancellation" {
  let started : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
  let stopped : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
  let replies : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  let token = @runtime.CancellationToken::new()
  let server = MCPServer::MCPServer("test", "1").tool(
    "late",
    "Late",
    { "type": "object" },
    (_, _) => {
      defer ignore(stopped.try_put(()) catch { _ => false })
      started.put(())
      @async.sleep(10000) catch {
        _ => ()
      }
      Ok(@tool.ToolResult::text("late"))
    },
  )
  @async.with_task_group(group => {
    server.handle_server_request(
      { message: runtime_request(1, "late", {}), reply: replies, },
      group,
      cancellation_token=token,
    )
    ignore(started.get())
    token.cancel()
    ignore(stopped.get())
  })
  assert_true(token.is_cancelled())
  assert_true(server.active_requests.is_empty())
  assert_true(replies.try_get() is None)
}
