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
    // `notifications` is a boolean opt-in object (SubscriptionFilter), with
    // only the enabled channels present.
    let notifications = match params.get("notifications") {
      Some(Object(n)) => n
      _ => panic()
    }
    assert_eq(notifications.get("toolsListChanged"), Some(Json::boolean(true)))
    assert_eq(
      notifications.get("resourcesListChanged"),
      Some(Json::boolean(true)),
    )
    assert_eq(notifications.contains("promptsListChanged"), false)
    // `resourceSubscriptions` nests inside `notifications` and is omitted
    // when empty.
    assert_eq(notifications.contains("resourceSubscriptions"), false)
    assert_eq(params.contains("resourceSubscriptions"), false)
  } else {
    panic()
  }
}

///|
test "build_subscriptions_listen_request nests resourceSubscriptions in notifications" {
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
    let notifications = match params.get("notifications") {
      Some(Object(n)) => n
      _ => panic()
    }
    let subs = match notifications.get("resourceSubscriptions") {
      Some(Array(a)) => a
      _ => panic()
    }
    @debug.assert_eq(subs.length(), 2)
    assert_eq(subs[0], Json::string("file:///a.txt"))
    assert_eq(params.contains("resourceSubscriptions"), false)
  } else {
    panic()
  }
}

///|
test "build_subscriptions_listen_request emits spec-shaped params" {
  let filter = {
    tools_list_changed: true,
    prompts_list_changed: true,
    resources_list_changed: true,
    resource_subscriptions: ["file:///notes.txt"],
  }
  let req = build_subscriptions_listen_request(9, test_meta(), filter)
  let actual = @json.parse(req) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"subscriptions/listen\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{},\"io.modelcontextprotocol/clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0.0\"}},\"notifications\":{\"toolsListChanged\":true,\"promptsListChanged\":true,\"resourcesListChanged\":true,\"resourceSubscriptions\":[\"file:///notes.txt\"]}}}",
  ) catch {
    _ => Json::null()
  }
  @debug.assert_eq(actual, expected)
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

/// === completion/complete result parsing (A7) ===

///|
test "parse_completion_result reads nested completion object" {
  let result = @json.parse(
    "{\"completion\":{\"values\":[\"red\",\"blue\"],\"total\":10,\"hasMore\":true}}",
  ) catch {
    _ => panic()
  }
  match parse_completion_result(result) {
    Ok(r) => {
      @debug.assert_eq(r.values, ["red", "blue"])
      assert_eq(r.total, Some(10))
      assert_eq(r.has_more, Some(true))
    }
    Err(_) => panic()
  }
}

///|
test "parse_completion_result with optional fields omitted" {
  let result = @json.parse("{\"completion\":{\"values\":[]}}") catch {
    _ => panic()
  }
  match parse_completion_result(result) {
    Ok(r) => {
      @debug.assert_eq(r.values.length(), 0)
      assert_eq(r.total, None)
      assert_eq(r.has_more, None)
    }
    Err(_) => panic()
  }
}

///|
test "parse_completion_result rejects missing completion object" {
  // Top-level values (the pre-2026-07-28 layout) must no longer parse.
  let result = @json.parse("{\"values\":[\"red\"],\"total\":1}") catch {
    _ => panic()
  }
  match parse_completion_result(result) {
    Err(@types.InvalidParams(_)) => ()
    _ => panic()
  }
}

///|
test "parse_completion_result rejects non-object completion" {
  let result = @json.parse("{\"completion\":[\"red\"]}") catch { _ => panic() }
  match parse_completion_result(result) {
    Err(@types.InvalidParams(_)) => ()
    _ => panic()
  }
}

/// === cancel_request transport gating (A9a) ===

///|
async test "cancel_request on HTTP transport rejects with SSE-stream guidance" {
  let transport = @transport.AnyTransport::HttpClient(
    @transport.HttpClientTransport::HttpClientTransport("http://127.0.0.1:9/"),
  )
  let client = MCPClient::MCPClient(name="t", version="1", transport~)
  match client.cancel_request("1") {
    Err(@types.InternalError(msg)) =>
      assert_true(msg.contains("closing the SSE response stream"))
    _ => panic()
  }
}

/// === RequestId JSON serialization (A9e) ===

///|
test "RequestId::to_json_string escapes control characters as valid JSON" {
  @debug.assert_eq(@types.RequestId::Str("plain").to_json_string(), "\"plain\"")
  @debug.assert_eq(@types.RequestId::Int(42).to_json_string(), "42")
  // \b, \f and other control chars < 0x20 must round-trip as valid JSON.
  let raw = "a\b\f\u{0001}z"
  let encoded = @types.RequestId::Str(raw).to_json_string()
  let reparsed = @json.parse(encoded) catch { _ => panic() }
  assert_eq(reparsed, Json::string(raw))
}
