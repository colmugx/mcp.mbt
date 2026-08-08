///|
/// Fixed `_meta` used by request-builder tests below. Kept stable so the
/// expected JSON snapshots remain deterministic.
fn test_meta() -> Json {
  build_request_meta("test-client", "1.0.0", {
    roots: None,
    sampling: None,
    elicitation: None,
  })
}

///|
test "MCPClient creates client with info" {
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::StdioTransport(),
  )
  let client = MCPClient::MCPClient(
    name="test-client",
    version="1.0.0",
    transport~,
  )
  @debug.assert_eq(client.client_name, "test-client")
  @debug.assert_eq(client.client_version, "1.0.0")
}

///|
test "MCPClient next_id increments" {
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::StdioTransport(),
  )
  let client = MCPClient::MCPClient(name="test", version="1.0", transport~)
  let id1 = client.next_request_id()
  let id2 = client.next_request_id()
  @debug.assert_eq(id1, 1)
  @debug.assert_eq(id2, 2)
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
  let actual = @json.parse(req) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"roots\":{\"listChanged\":true},\"sampling\":{}},\"clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0.0\"}}}",
  ) catch {
    _ => Json::null()
  }
  @debug.assert_eq(actual, expected)
}

///|
test "build_initialize_request with elicitation uses empty object" {
  let caps : @types.ClientCapabilities = {
    roots: None,
    sampling: None,
    elicitation: Some(@types.ElicitationCapabilities::{ form: true }),
  }
  let req = build_initialize_request(
    1,
    "test-client",
    "1.0.0",
    capabilities=caps,
  )
  let actual = @json.parse(req) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"elicitation\":{\"form\":{}}},\"clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0.0\"}}}",
  ) catch {
    _ => Json::null()
  }
  @debug.assert_eq(actual, expected)
}

///|
test "build_ping_request format" {
  let req = build_ping_request(42)
  let actual = @json.parse(req) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"ping\"}",
  ) catch {
    _ => Json::null()
  }
  @debug.assert_eq(actual, expected)
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
test "build_initialized_notification format" {
  let notif = build_initialized_notification()
  let actual = @json.parse(notif) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
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
test "build_set_log_level_request format" {
  let req = build_set_log_level_request(1, "info")
  let actual = @json.parse(req) catch { _ => Json::null() }
  let expected = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"logging/setLevel\",\"params\":{\"level\":\"info\"}}",
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
