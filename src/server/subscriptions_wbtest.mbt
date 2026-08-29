///| subscriptions/listen tests (white-box)
///
/// Verifies the acknowledgment shape, filter parsing, and that change
/// notifications route to the right subscription stream tagged with the
/// subscription id.

///|
/// Build a SubscriptionRequest with a toolsListChanged filter.
fn tools_filter() -> SubscriptionFilter {
  { ..SubscriptionFilter::empty(), tools_list_changed: true, }
}

///|
test "subscriptions: acknowledged carries subscriptionId and agreed filter" {
  let id = @types.RequestId::Int(7)
  let filter = tools_filter()
  let ack = subscriptions_acknowledged_str(id, filter)
  let json = @json.parse(ack) catch { _ => panic() }
  if json is Object(obj) {
    assert_eq(
      obj.get("method"),
      Some(Json::string("notifications/subscriptions/acknowledged")),
    )
    let params = obj.get("params")
    match params {
      Some(Object(p)) => {
        let meta = p.get("_meta")
        match meta {
          Some(Object(m)) =>
            assert_eq(
              m.get("io.modelcontextprotocol/subscriptionId"),
              Some(Json::number(7.0)),
            )
          _ => panic()
        }
        // toolsListChanged agreed; the other fields absent.
        match p.get("notifications") {
          Some(Object(n)) =>
            assert_eq(n.get("toolsListChanged"), Some(Json::boolean(true)))
          _ => panic()
        }
      }
      _ => panic()
    }
  } else {
    panic()
  }
}

///|
test "subscriptions: parse_subscription_filter reads all fields" {
  let params = Json::object({
    "notifications": Json::object({
      "toolsListChanged": Json::boolean(true),
      "resourcesListChanged": Json::boolean(true),
      "resourceSubscriptions": Json::array([
        Json::string("file:///a"),
        Json::string("file:///b"),
      ]),
    }),
  })
  let filter = parse_subscription_filter(params)
  assert_true(filter.tools_list_changed)
  assert_false(filter.prompts_list_changed)
  assert_true(filter.resources_list_changed)
  assert_eq(filter.resource_subscriptions.length(), 2)
}

///|
#cfg(not(target="wasm-gc"))
async test "subscriptions: notify_tools_list_changed routes to matching stream" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  // Stand up a fake reply queue (as stdio transport uses).
  let reply_queue : @aqueue.Queue[String] = @aqueue.Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  // Register a subscription with id "1" and a tools-list filter.
  server.subscriptions.set("1", {
    filter: tools_filter(),
    reply: ReplyHandle::Stdio(reply_queue),
  })
  // Trigger a tools-list-changed notification.
  server.notify_tools_list_changed()
  // The first message on the queue should be the tagged notification.
  let msg = reply_queue.try_get() catch { _ => panic() }
  match msg {
    Some(json_str) => {
      let json = @json.parse(json_str) catch { _ => panic() }
      if json is Object(obj) {
        assert_eq(
          obj.get("method"),
          Some(Json::string("notifications/tools/list_changed")),
        )
        let meta = match obj.get("params") {
          Some(Object(params_map)) => params_map.get("_meta")
          _ => panic()
        }
        match meta {
          Some(Object(m)) =>
            assert_eq(
              m.get("io.modelcontextprotocol/subscriptionId"),
              Some(Json::string("1")),
            )
          _ => panic()
        }
      } else {
        panic()
      }
    }
    None => panic()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "subscriptions: non-matching filter receives no notification" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let reply_queue : @aqueue.Queue[String] = @aqueue.Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  // Subscribe only to prompts-list-changed.
  server.subscriptions.set("2", {
    filter: { ..SubscriptionFilter::empty(), prompts_list_changed: true, },
    reply: ReplyHandle::Stdio(reply_queue),
  })
  // A tools-list-changed notification should NOT land on this stream.
  server.notify_tools_list_changed()
  let msg = reply_queue.try_get() catch { _ => None }
  match msg {
    Some(_) => panic() // unexpected notification
    None => ()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "subscriptions: notify_resource_updated reaches only matching URI subscribers" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let sub_a : @aqueue.Queue[String] = @aqueue.Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  let sub_b : @aqueue.Queue[String] = @aqueue.Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  server.subscriptions.set("1", {
    filter: {
      ..SubscriptionFilter::empty(),
      resource_subscriptions: ["file:///watched"],
    },
    reply: ReplyHandle::Stdio(sub_a),
  })
  server.subscriptions.set("2", {
    filter: {
      ..SubscriptionFilter::empty(),
      resource_subscriptions: ["file:///other"],
    },
    reply: ReplyHandle::Stdio(sub_b),
  })
  server.notify_resource_updated("file:///watched")
  // Sub 1 receives the update, tagged with its subscription id.
  let msg_a = sub_a.try_get() catch { _ => None }
  match msg_a {
    Some(json_str) => {
      let json = @json.parse(json_str) catch { _ => panic() }
      if json is Object(obj) {
        assert_eq(
          obj.get("method"),
          Some(Json::string("notifications/resources/updated")),
        )
        let params = match obj.get("params") {
          Some(Object(p)) => p
          _ => panic()
        }
        assert_eq(params.get("uri"), Some(Json::string("file:///watched")))
        match params.get("_meta") {
          Some(Object(m)) =>
            assert_eq(
              m.get("io.modelcontextprotocol/subscriptionId"),
              Some(Json::string("1")),
            )
          _ => panic()
        }
      } else {
        panic()
      }
    }
    None => panic()
  }
  // Sub 2 (different URI) receives nothing.
  let msg_b = sub_b.try_get() catch { _ => None }
  match msg_b {
    Some(_) => panic()
    None => ()
  }
}
