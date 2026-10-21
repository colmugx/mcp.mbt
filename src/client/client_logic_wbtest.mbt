// MCPClient pure-logic tests. The dummy transport is an HttpClient one that
// is only constructed, never sent on (safe on js too — see
// response_pump_wbtest.mbt); wasm-gc has no HttpClientTransport and is gated
// out by moon.pkg targets.

///|
fn logic_client(name~ : String = "t", version~ : String = "1") -> MCPClient {
  let transport = @transport.AnyTransport::HttpClient(
    @transport.HttpClientTransport::HttpClientTransport("http://unused.invalid"),
  )
  MCPClient::MCPClient(name~, version~, transport~)
}

///|
test "MCPClient creates client with info" {
  let client = logic_client(name="test-client", version="1.0.0")
  @debug.assert_eq(client.client_name, "test-client")
  @debug.assert_eq(client.client_version, "1.0.0")
}

///|
test "MCPClient next_id increments" {
  let client = logic_client()
  let id1 = client.next_request_id()
  let id2 = client.next_request_id()
  @debug.assert_eq(id1, 1)
  @debug.assert_eq(id2, 2)
}

///|
/// `check_input_required` detects an input_required result and extracts the
/// requestState + inputRequests; complete results yield None; an
/// unrecognized non-empty resultType raises InvalidParams.
fn mrtr_complete_response() -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"resultType\":\"complete\"}}"
}

///|
fn mrtr_no_result_type_response() -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"values\":[]}}"
}

///|
fn mrtr_unknown_result_type_response() -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"resultType\":\"partially_done\"}}"
}

///|
fn mrtr_input_required_response() -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"resultType\":\"input_required\",\"requestState\":\"blob\",\"inputRequests\":{\"login\":{\"method\":\"elicitation/create\",\"params\":{\"message\":\"user\"}}}}}"
}

///|
test "mrtr: complete response is not input_required" {
  try logic_client().check_input_required(mrtr_complete_response()) catch {
    _ => panic()
  } noraise {
    None => ()
    _ => fail("expected complete response")
  }
}

///|
test "mrtr: absent resultType is treated as complete" {
  try
    logic_client().check_input_required(mrtr_no_result_type_response())
  catch {
    _ => panic()
  } noraise {
    None => ()
    _ => fail("expected complete response")
  }
}

///|
test "mrtr: unrecognized resultType is an InvalidParams error" {
  try
    logic_client().check_input_required(mrtr_unknown_result_type_response())
  catch {
    @types.InvalidParams(msg) => assert_true(msg.contains("partially_done"))
    _ => panic()
  } noraise {
    _ => panic()
  }
}

///|
test "mrtr: non-string resultType is an InvalidParams error" {
  let response = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"resultType\":7}}"
  try logic_client().check_input_required(response) catch {
    @types.InvalidParams(_) => ()
    _ => panic()
  } noraise {
    _ => panic()
  }
}

///|
test "mrtr: input_required response extracts requestState and inputRequests" {
  try
    logic_client().check_input_required(mrtr_input_required_response())
  catch {
    _ => panic()
  } noraise {
    Some(info) => {
      assert_eq(info.request_state, Some("blob"))
      match info.input_requests.get("login") {
        Some((method_name, _)) => assert_eq(method_name, "elicitation/create")
        None => panic()
      }
    }
    None => fail("expected input_required response")
  }
}

///|
test "set_legacy_mode toggles the legacy_mode field" {
  let client = logic_client()
  @debug.assert_eq(client.legacy_mode, false)
  let legacy = client.set_legacy_mode(true)
  @debug.assert_eq(legacy.legacy_mode, true)
}

///|
test "maybe_store_server_info stores serverInfo from result _meta" {
  let client = logic_client()
  let response = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"_meta\":{\"io.modelcontextprotocol/serverInfo\":{\"name\":\"test-server\",\"version\":\"2.0\"}}}}"
  client.maybe_store_server_info(response)
  match client.server_info {
    Some(info) => {
      @debug.assert_eq(info.name, "test-server")
      @debug.assert_eq(info.version, "2.0")
    }
    None => panic()
  }
}
