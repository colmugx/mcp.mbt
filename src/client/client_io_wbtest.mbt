// MCPClient tests that construct a Stdio-backed transport. Gated to
// native+wasm: on js the StdioTransport stub aborts (support matrix — client
// is native+js for HttpClientTransport only), and wasm-gc has no transport.

///|
#cfg(any(target="native", target="wasm"))
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
#cfg(any(target="native", target="wasm"))
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
/// `check_input_required` detects an input_required result and extracts the
/// requestState + inputRequests; complete results yield None.
#cfg(any(target="native", target="wasm"))
fn mrtr_complete_response() -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"resultType\":\"complete\"}}"
}

///|
#cfg(any(target="native", target="wasm"))
fn mrtr_input_required_response() -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"resultType\":\"input_required\",\"requestState\":\"blob\",\"inputRequests\":{\"login\":{\"method\":\"elicitation/create\",\"params\":{\"message\":\"user\"}}}}}"
}

///|
#cfg(any(target="native", target="wasm"))
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
#cfg(any(target="native", target="wasm"))
test "mrtr: input_required response extracts requestState and inputRequests" {
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::StdioTransport(),
  )
  let client = MCPClient::MCPClient(name="t", version="1", transport~)
  match client.check_input_required(mrtr_input_required_response()) {
    Some(info) => {
      assert_eq(info.request_state, Some("blob"))
      match info.input_requests.get("login") {
        Some((method_name, _)) => assert_eq(method_name, "elicitation/create")
        None => panic()
      }
    }
    None => panic()
  }
}

///|
#cfg(any(target="native", target="wasm"))
test "set_legacy_mode toggles the legacy_mode field" {
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::StdioTransport(),
  )
  let client = MCPClient::MCPClient(name="t", version="1", transport~)
  @debug.assert_eq(client.legacy_mode, false)
  let legacy = client.set_legacy_mode(true)
  @debug.assert_eq(legacy.legacy_mode, true)
}

///|
#cfg(any(target="native", target="wasm"))
test "maybe_store_server_info stores serverInfo from result _meta" {
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::StdioTransport(),
  )
  let client = MCPClient::MCPClient(name="t", version="1", transport~)
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
