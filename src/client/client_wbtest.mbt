///|
/// Fixed `_meta` used by request-builder tests below. Kept stable so the
/// expected JSON snapshots remain deterministic.
fn test_meta() -> Json {
  build_request_meta("test-client", "1.0.0", {
    roots: None,
    sampling: None,
    elicitation: None,
    extensions: None,
  })
}

///|
test "build_tools_list_request format" {
  let req = build_tools_list_request(1, test_meta())
  let actual = @json.parse(req) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{},\"io.modelcontextprotocol/clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0.0\"}}}}",
  ) catch {
    _ => Json::null()
  }
  @debug.assert_eq(actual, expected)
}

///|
test "build_tools_call_request format" {
  let req = build_tools_call_request(
    1,
    "my_tool",
    test_meta(),
    arguments="{\"x\": 1}",
  )
  let actual = @json.parse(req) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"my_tool\",\"arguments\":{\"x\":1},\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{},\"io.modelcontextprotocol/clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0.0\"}}}}",
  ) catch {
    _ => Json::null()
  }
  @debug.assert_eq(actual, expected)
}

///|
test "build_resources_list_request format" {
  let req = build_resources_list_request(1, test_meta())
  let actual = @json.parse(req) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"resources/list\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{},\"io.modelcontextprotocol/clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0.0\"}}}}",
  ) catch {
    _ => Json::null()
  }
  @debug.assert_eq(actual, expected)
}

///|
test "build_resources_read_request format" {
  let req = build_resources_read_request(1, "file:///test.txt", test_meta())
  let actual = @json.parse(req) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"resources/read\",\"params\":{\"uri\":\"file:///test.txt\",\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{},\"io.modelcontextprotocol/clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0.0\"}}}}",
  ) catch {
    _ => Json::null()
  }
  @debug.assert_eq(actual, expected)
}

///|
test "build_prompts_list_request format" {
  let req = build_prompts_list_request(1, test_meta())
  let actual = @json.parse(req) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"prompts/list\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{},\"io.modelcontextprotocol/clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0.0\"}}}}",
  ) catch {
    _ => Json::null()
  }
  @debug.assert_eq(actual, expected)
}

///|
test "build_prompts_get_request format" {
  let req = build_prompts_get_request(
    1,
    "my_prompt",
    test_meta(),
    arguments="{\"key\": \"val\"}",
  )
  let actual = @json.parse(req) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"prompts/get\",\"params\":{\"name\":\"my_prompt\",\"arguments\":{\"key\":\"val\"},\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{},\"io.modelcontextprotocol/clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0.0\"}}}}",
  ) catch {
    _ => Json::null()
  }
  @debug.assert_eq(actual, expected)
}

///|
test "handle_server_notification dispatches tools changed" {
  let mut called = false
  let handlers : NotificationHandlers = {
    ..NotificationHandlers::empty(),
    on_tools_changed: Some(fn() { called = true }),
  }
  let notification = @types.tools_list_changed_notification()
  handle_server_notification(handlers, notification)
  @debug.assert_eq(called, true)
}

///|
test "handle_server_notification dispatches resources changed" {
  let mut called = false
  let handlers : NotificationHandlers = {
    ..NotificationHandlers::empty(),
    on_resources_changed: Some(fn() { called = true }),
  }
  let notification = @types.resources_list_changed_notification()
  handle_server_notification(handlers, notification)
  @debug.assert_eq(called, true)
}

///|
test "handle_server_notification dispatches prompts changed" {
  let mut called = false
  let handlers : NotificationHandlers = {
    ..NotificationHandlers::empty(),
    on_prompts_changed: Some(fn() { called = true }),
  }
  let notification = @types.prompts_list_changed_notification()
  handle_server_notification(handlers, notification)
  @debug.assert_eq(called, true)
}

///|
test "handle_server_notification ignores unknown notification" {
  let handlers = NotificationHandlers::empty()
  let notification : @types.Notification = {
    method_name: "notifications/unknown",
    params: None,
  }
  handle_server_notification(handlers, notification)
}

///|
test "build_discover_request format" {
  let req = build_discover_request(1, test_meta())
  let actual = @json.parse(req) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"server/discover\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{},\"io.modelcontextprotocol/clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0.0\"}}}}",
  ) catch {
    _ => Json::null()
  }
  @debug.assert_eq(actual, expected)
}

///|
test "mrtr: build_retry_request attaches inputResponses and requestState with new id" {
  let original = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"get_weather\",\"arguments\":{\"city\":\"Seattle\"},\"_meta\":{}}}"
  let responses : Map[String, Json] = Default::default()
  responses.set("login", Json::object({ "action": Json::string("accept") }))
  let retry = build_retry_request(original, 99, responses, Some("blob"))
  let json = @json.parse(retry) catch { _ => panic() }
  if json is Object(obj) {
    // New id assigned
    assert_eq(obj.get("id"), Some(Json::number(99.0)))
    let params = match obj.get("params") {
      Some(Object(p)) => p
      _ => panic()
    }
    // Original params preserved
    assert_eq(params.get("name"), Some(Json::string("get_weather")))
    // inputResponses attached
    match params.get("inputResponses") {
      Some(Object(r)) => assert_true(r.contains("login"))
      _ => panic()
    }
    // requestState echoed
    assert_eq(params.get("requestState"), Some(Json::string("blob")))
  } else {
    panic()
  }
}

///|
test "build_subscriptions_listen_request includes enabled channels only" {
  let filter = {
    tools_list_changed: true,
    prompts_list_changed: false,
    resources_list_changed: true,
    resource_subscriptions: [],
  }
  let req = build_subscriptions_listen_request(7, test_meta(), filter)
  let json = @json.parse(req) catch { _ => Json::null() }
  if json is Object(obj) {
    assert_eq(obj.get("method"), Some(Json::string("subscriptions/listen")))
    assert_eq(obj.get("id"), Some(Json::number(7.0)))
    let params = match obj.get("params") {
      Some(Object(p)) => p
      _ => panic()
    }
    let notifications = match params.get("notifications") {
      Some(Array(a)) => a.map(fn(j) { j.stringify() })
      _ => panic()
    }
    @debug.assert_eq(notifications.length(), 2)
    assert_true(notifications.contains("\"notifications/tools/list_changed\""))
    assert_true(
      notifications.contains("\"notifications/resources/list_changed\""),
    )
    assert_eq(params.contains("resourceSubscriptions"), false)
  } else {
    panic()
  }
}

///|
test "build_subscriptions_listen_request includes resourceSubscriptions when set" {
  let filter = {
    tools_list_changed: false,
    prompts_list_changed: false,
    resources_list_changed: false,
    resource_subscriptions: ["file:///a.txt", "file:///b.txt"],
  }
  let req = build_subscriptions_listen_request(8, test_meta(), filter)
  let json = @json.parse(req) catch { _ => Json::null() }
  if json is Object(obj) {
    let params = match obj.get("params") {
      Some(Object(p)) => p
      _ => panic()
    }
    let subs = match params.get("resourceSubscriptions") {
      Some(Array(a)) => a
      _ => panic()
    }
    @debug.assert_eq(subs.length(), 2)
    assert_eq(subs[0], Json::string("file:///a.txt"))
  } else {
    panic()
  }
}

///|
test "extract_subscription_id accepts Number and String ids" {
  let number_params = @json.parse(
    "{\"_meta\":{\"io.modelcontextprotocol/subscriptionId\":42}}",
  ) catch {
    _ => panic()
  }
  assert_eq(extract_subscription_id(Some(number_params)), Some("42"))
  let string_params = @json.parse(
    "{\"_meta\":{\"io.modelcontextprotocol/subscriptionId\":\"sub-abc\"}}",
  ) catch {
    _ => panic()
  }
  assert_eq(extract_subscription_id(Some(string_params)), Some("sub-abc"))
  assert_eq(extract_subscription_id(None), None)
}

///|
fn schema_with_x_mcp_header(type_ : String, header : String) -> Json {
  @json.parse(
    "{\"type\":\"object\",\"properties\":{\"p\":{\"type\":\"" +
    type_ +
    "\",\"x-mcp-header\":\"" +
    header +
    "\"}}}",
  ) catch {
    _ => Json::null()
  }
}

///|
test "x-mcp-header: valid nested properties" {
  let schema = @json.parse(
    "{\"type\":\"object\",\"properties\":{\"outer\":{\"type\":\"object\",\"properties\":{\"inner\":{\"type\":\"string\",\"x-mcp-header\":\"X-Custom\"}}}}}",
  ) catch {
    _ => Json::null()
  }
  match validate_tool_header_schema(schema) {
    Valid(entries) => {
      @debug.assert_eq(entries.length(), 1)
      @debug.assert_eq(entries[0].0, ["outer", "inner"])
      @debug.assert_eq(entries[0].1, "X-Custom")
    }
    Invalid(_) => panic()
  }
}

///|
test "x-mcp-header: rejects invalid token characters" {
  match
    validate_tool_header_schema(
      schema_with_x_mcp_header("string", "Bad Header"),
    ) {
    Invalid(_) => ()
    Valid(_) => panic()
  }
}

///|
test "x-mcp-header: rejects number typed property" {
  match
    validate_tool_header_schema(schema_with_x_mcp_header("number", "X-Num")) {
    Invalid(_) => ()
    Valid(_) => panic()
  }
}

///|
test "x-mcp-header: rejects annotation under items" {
  let schema = @json.parse(
    "{\"type\":\"object\",\"properties\":{\"p\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"x-mcp-header\":\"X-Bad\"}}}}",
  ) catch {
    _ => Json::null()
  }
  match validate_tool_header_schema(schema) {
    Invalid(_) => ()
    Valid(_) => panic()
  }
}

///|
test "x-mcp-header: rejects case-insensitive duplicate header names" {
  let schema = @json.parse(
    "{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"string\",\"x-mcp-header\":\"X-Foo\"},\"b\":{\"type\":\"string\",\"x-mcp-header\":\"x-foo\"}}}",
  ) catch {
    _ => Json::null()
  }
  match validate_tool_header_schema(schema) {
    Invalid(_) => ()
    Valid(_) => panic()
  }
}

///|
test "x-mcp-header: rejects annotation at root schema" {
  let schema = @json.parse("{\"type\":\"object\",\"x-mcp-header\":\"X-Root\"}") catch {
    _ => Json::null()
  }
  match validate_tool_header_schema(schema) {
    Invalid(_) => ()
    Valid(_) => panic()
  }
}
