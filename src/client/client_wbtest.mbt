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
/// `check_input_required` detects an input_required result and extracts the
/// requestState + inputRequests; complete results yield None.
fn mrtr_complete_response() -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"resultType\":\"complete\"}}"
}

///|
fn mrtr_input_required_response() -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"resultType\":\"input_required\",\"requestState\":\"blob\",\"inputRequests\":{\"login\":{\"method\":\"elicitation/create\",\"params\":{\"message\":\"user\"}}}}}"
}

///|
test "mrtr: complete response is not input_required" {
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::StdioTransport(),
  )
  let client = MCPClient::MCPClient(name="t", version="1", transport~)
  match client.check_input_required(mrtr_complete_response()) {
    Some(_) => panic()
    None => ()
  }
}

///|
test "mrtr: input_required response extracts requestState and inputRequests" {
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::StdioTransport(),
  )
  let client = MCPClient::MCPClient(name="t", version="1", transport~)
  match client.check_input_required(mrtr_input_required_response()) {
    Some(info) => {
      assert_eq(info.request_state, Some("blob"))
      match info.input_requests.get("login") {
        Some((method, _)) => assert_eq(method, "elicitation/create")
        None => panic()
      }
    }
    None => panic()
  }
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
