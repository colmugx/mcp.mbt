///|
async test "server replies echo exact numeric and string ids and reject fractions" {
  let server = MCPServer::MCPServer("test", "1").tool(
    "echo",
    "Echo",
    { "type": "object" },
    (_, _) => Ok(@tool.ToolResult::text("ok")),
  )
  for
    literal in [
      "2147483648", "9007199254740993", "1.23e4", "1e100000000000000000000", "\"9007199254740993\"",
      "\"escaped\\n\\\"id\"",
    ] {
    let request = @validation.parse_json(runtime_request(1, "echo", {}))
    guard request is Object(fields) else { fail("expected request") }
    fields["id"] = @validation.parse_json(literal)
    let response = @validation.parse_json(
      server.handle_request(request.stringify()),
    )
    guard response is Object(reply) && reply.get("id") is Some(id) else {
      fail("missing response id")
    }
    assert_eq(@types.RequestId::from_json(id).to_json_string(), literal)
    assert_true(reply.contains("result"))
  }
  let response = @validation.parse_json(
    server.handle_request(
      "{\"jsonrpc\":\"2.0\",\"id\":1.00000000000000000001,\"method\":\"tools/list\"}",
    ),
  )
  guard response is Object(fields) else { fail("expected response") }
  assert_true(response is { "error": { "code": Number(-32600, ..), .. }, .. })
  assert_false(fields.contains("id"))
}

///|
async test "server active-id ownership and cancellation use exact typed numeric identity" {
  let started : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  let stopped : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  let replies : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  let duplicate : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  let server = MCPServer::MCPServer("test", "1").tool(
    "slow",
    "Slow",
    { "type": "object" },
    (context, _) => {
      let id = context.request_id.to_json_string()
      defer ignore(stopped.try_put(id) catch { _ => false })
      started.put(id)
      @async.sleep(10000)
      Ok(@tool.ToolResult::text("must not be emitted"))
    },
  )
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      for
        literal in [
          "9007199254740992", "9007199254740993", "\"9007199254740993\"", "90071992547409930e-1",
        ] {
        let request = @validation.parse_json(runtime_request(1, "slow", {}))
        guard request is Object(fields) else { fail("expected request") }
        fields["id"] = @validation.parse_json(literal)
        server.handle_server_request(
          {
            message: request.stringify(),
            reply: if literal == "90071992547409930e-1" {
              duplicate
            } else {
              replies
            },
          },
          group,
          scope="peer",
        )
      }
      for _ in 0..<3 {
        ignore(started.get())
      }
      assert_eq(server.active_requests.length(), 3)
      assert_true(
        @validation.parse_json(duplicate.get())
        is { "error": { "code": Number(-32600, ..), .. }, .. },
      )
      server.handle_inbound_notification(
        "{\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":9007199254740993.1}}",
        scope="peer",
      )
      assert_eq(server.active_requests.length(), 3)
      server.handle_inbound_notification(
        "{\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":\"9007199254740993\"}}",
        scope="peer",
      )
      assert_eq(stopped.get(), "\"9007199254740993\"")
      server.handle_inbound_notification(
        "{\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":90071992547409930e-1}}",
        scope="peer",
      )
      assert_eq(stopped.get(), "9007199254740993")
      assert_eq(server.active_requests.length(), 1)
      server.handle_inbound_notification(
        "{\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":9007199254740992}}",
        scope="peer",
      )
      assert_eq(stopped.get(), "9007199254740992")
    })
  })
  assert_true(server.active_requests.is_empty())
  assert_true(replies.try_get() is None)
}

///|
async test "subscription tags and graceful completion retain the original id type and literal" {
  let server = MCPServer::MCPServer("test", "1")
  for literal in ["9007199254740993", "\"9007199254740993\"", "4.2e1"] {
    let reply : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
    let id = @types.RequestId::from_json(@validation.parse_json(literal))
    let request : @types.JsonRpcRequest = {
      jsonrpc: "2.0",
      id,
      method_name: "subscriptions/listen",
      params: { "notifications": {} },
    }
    server.handle_subscriptions_listen(request, reply)
    ignore(reply.try_get())
    let notification = @validation.parse_json(
      tag_notification_with_subscription(
        "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/tools/list_changed\"}",
        literal,
      ),
    )
    guard notification
      is {
        "params": {
          "_meta": { "io.modelcontextprotocol/subscriptionId": tagged, .. },
          ..
        },
        ..
      } else {
      fail("missing subscription tag")
    }
    assert_eq(@types.RequestId::from_json(tagged).to_json_string(), literal)
    server.close_subscription(if literal == "4.2e1" { "42" } else { literal })
    let completed = @validation.parse_json(reply.try_get().unwrap())
    guard completed
      is {
        "id": completed_id,
        "result": {
          "_meta": {
            "io.modelcontextprotocol/subscriptionId": completed_tag,
            ..
          },
          ..
        },
        ..
      } else {
      fail("missing completion ids")
    }
    assert_eq(
      @types.RequestId::from_json(completed_id).to_json_string(),
      literal,
    )
    assert_eq(
      @types.RequestId::from_json(completed_tag).to_json_string(),
      literal,
    )
  }
  assert_true(server.subscriptions.is_empty())
}
