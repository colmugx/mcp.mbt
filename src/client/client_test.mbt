///|
test "MCPClient::new creates client with info" {
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::new(),
  )
  let client = MCPClient::new(name="test-client", version="1.0.0", transport~)
  assert_eq(client.client_name, "test-client")
  assert_eq(client.client_version, "1.0.0")
}

///|
test "MCPClient next_id increments" {
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::new(),
  )
  let client = MCPClient::new(name="test", version="1.0", transport~)
  let id1 = client.next_request_id()
  let id2 = client.next_request_id()
  assert_eq(id1, 1)
  assert_eq(id2, 2)
}

///|
test "build_initialize_request format" {
  let caps : @types.ClientCapabilities = {
    roots: Some({ list_changed: true }),
    sampling: Some(@types.SamplingCapabilities::{  }),
    elicitation: None,
  }
  let req = build_initialize_request(
    1,
    "test-client",
    "1.0.0",
    capabilities=caps,
  )
  assert_eq(
    req, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"roots\":{\"listChanged\":true},\"sampling\":{}},\"clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0.0\"}}}",
  )
}

///|
test "build_ping_request format" {
  let req = build_ping_request(42)
  assert_eq(req, "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"ping\"}")
}

///|
test "build_tools_list_request format" {
  let req = build_tools_list_request(1)
  assert_eq(req, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}")
}

///|
test "build_tools_call_request format" {
  let req = build_tools_call_request(1, "my_tool", arguments="{\"x\": 1}")
  assert_eq(
    req, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"my_tool\",\"arguments\":{\"x\": 1}}}",
  )
}

///|
test "build_initialized_notification format" {
  let notif = build_initialized_notification()
  assert_eq(
    notif, "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
  )
}

///|
test "build_resources_list_request format" {
  let req = build_resources_list_request(1)
  assert_eq(req, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"resources/list\"}")
}

///|
test "build_resources_read_request format" {
  let req = build_resources_read_request(1, "file:///test.txt")
  assert_eq(
    req, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"resources/read\",\"params\":{\"uri\":\"file:///test.txt\"}}",
  )
}

///|
test "build_prompts_list_request format" {
  let req = build_prompts_list_request(1)
  assert_eq(req, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"prompts/list\"}")
}

///|
test "build_prompts_get_request format" {
  let req = build_prompts_get_request(
    1,
    "my_prompt",
    arguments="{\"key\": \"val\"}",
  )
  assert_eq(
    req, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"prompts/get\",\"params\":{\"name\":\"my_prompt\",\"arguments\":{\"key\": \"val\"}}}",
  )
}

///|
test "build_set_log_level_request format" {
  let req = build_set_log_level_request(1, "info")
  assert_eq(
    req, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"logging/setLevel\",\"params\":{\"level\":\"info\"}}",
  )
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
  assert_eq(called, true)
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
  assert_eq(called, true)
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
  assert_eq(called, true)
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
