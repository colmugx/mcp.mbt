///| MCP Protocol Compliance Tests

///|

///| Tests that verify the SDK's JSON-RPC responses conform to the

///| MCP 2026-07-28 specification.

///|
/// Helper: parse a JSON string and extract field as string
fn json_field_str(json : Json, field : String) -> String {
  if json is Object(obj) {
    match obj.get(field) {
      Some(String(s)) => s
      _ => panic()
    }
  } else {
    panic()
  }
}

///|
/// Helper: check if a Json object has a field
fn json_has(json : Json, field : String) -> Bool {
  if json is Object(obj) {
    obj.get(field) is Some(_)
  } else {
    false
  }
}

///|
/// Helper: get a field as Json
fn json_get(json : Json, field : String) -> Json {
  if json is Object(obj) {
    match obj.get(field) {
      Some(v) => v
      None => panic()
    }
  } else {
    panic()
  }
}

///|
/// Helper: get array length from Json
fn json_arr_len(json : Json) -> Int {
  if json is Array(arr) {
    arr.length()
  } else {
    panic()
  }
}

///|
/// Helper: parse response and extract result object
fn parse_result(response : String) -> Json {
  let json = @json.parse(response) catch { _ => panic() }
  json_get(json, "result")
}

///|
/// Helper: the `_meta` object every well-formed request must carry in its
/// `params` (spec basic/index#_meta) — required protocolVersion plus
/// clientCapabilities (an empty object = no optional capabilities).
fn valid_request_meta(client_capabilities? : Json = Json::object({})) -> Json {
  Json::object({
    "io.modelcontextprotocol/protocolVersion": Json::string(
      @types.ProtocolVersion,
    ),
    "io.modelcontextprotocol/clientCapabilities": client_capabilities,
  })
}

///| =====================================================

///| JSON-RPC Message Format

///|
/// =====================================================
test "compliance: response has jsonrpc 2.0" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let response = handle_tools_list(server, @types.RequestId::Int(1))
  let json = @json.parse(response) catch { _ => panic() }
  assert_eq(json_field_str(json, "jsonrpc"), "2.0")
}

///|
test "compliance: response id matches request id" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let response = handle_tools_list(server, @types.RequestId::Int(42))
  let json = @json.parse(response) catch { _ => panic() }
  match json {
    Object(obj) =>
      match obj.get("id") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 42)
        _ => panic()
      }
    _ => panic()
  }
}

///| =====================================================

///| server/discover

///|
/// =====================================================
test "compliance: discover returns supportedVersions and capabilities" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let result = parse_result(handle_discover(server, @types.RequestId::Int(1)))
  let versions = json_get(result, "supportedVersions")
  if versions is Array(arr) {
    assert_eq(arr.length(), 1)
    assert_eq(arr[0], Json::string("2026-07-28"))
  } else {
    panic()
  }
  let caps = json_get(result, "capabilities")
  assert_true(json_has(caps, "tools"))
  assert_true(json_has(caps, "resources"))
  assert_true(json_has(caps, "prompts"))
}

///|
test "compliance: discover carries serverInfo in _meta" {
  let server = MCPServer::MCPServer("discover-server", "2.5.0")
  let result = parse_result(handle_discover(server, @types.RequestId::Int(1)))
  let info = json_get(
    json_get(result, "_meta"),
    "io.modelcontextprotocol/serverInfo",
  )
  assert_eq(json_field_str(info, "name"), "discover-server")
  assert_eq(json_field_str(info, "version"), "2.5.0")
}

///|
test "compliance: cacheable results carry ttlMs and cacheScope" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let result = parse_result(handle_tools_list(server, @types.RequestId::Int(1)))
  assert_eq(json_field_str(result, "cacheScope"), "public")
  // ttlMs is a number field; verify it equals 60000.
  if result is Object(obj) {
    match obj.get("ttlMs") {
      Some(Number(n, ..)) => assert_eq(n.to_int(), 60000)
      _ => panic()
    }
  } else {
    panic()
  }
}

///| =====================================================

///| MRTR (resultType)

///|
/// =====================================================
test "compliance: result resultType is complete for normal responses" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let result = parse_result(handle_tools_list(server, @types.RequestId::Int(1)))
  assert_eq(json_field_str(result, "resultType"), "complete")
}

///|
test "compliance: input_required result carries inputRequests and requestState" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let reqs : Map[String, @types.InputRequestEntry] = Default::default()
  reqs.set("login", {
    method_name: @types.InputRequestKind::ElicitationCreate,
    params: Json::object({ "message": Json::string("Enter username") }),
  })
  let response = jsonrpc_input_required_str(
    server,
    @types.RequestId::Int(1),
    reqs,
    request_state=Some("opaque-blob"),
  )
  let result = parse_result(response)
  assert_eq(json_field_str(result, "resultType"), "input_required")
  assert_eq(json_field_str(result, "requestState"), "opaque-blob")
  let input_reqs = json_get(result, "inputRequests")
  if input_reqs is Object(obj) {
    let login = obj.get("login")
    match login {
      Some(Object(_)) => ()
      _ => panic()
    }
  } else {
    panic()
  }
}

///| =====================================================

///| tools/list

///|
/// =====================================================
test "compliance: tools/list returns array with name/description/inputSchema" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  server.register_tool(
    "echo",
    "Echo tool",
    Json::object({ "type": "object" }),
    fn(_args) {
      Ok(@tool.ToolCallOutcome::Complete(@tool.ToolResult::text("ok")))
    },
  )
  let result = parse_result(handle_tools_list(server, @types.RequestId::Int(1)))
  let tools = json_get(result, "tools")
  assert_eq(json_arr_len(tools), 1)
  if tools is Array(arr) {
    let t = arr[0]
    assert_true(json_has(t, "name"))
    assert_true(json_has(t, "description"))
    assert_true(json_has(t, "inputSchema"))
  } else {
    panic()
  }
}

///|
test "compliance: tools/list preserves tool name" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  server.register_tool(
    "my_tool",
    "My tool",
    Json::object({ "type": "object" }),
    fn(_args) {
      Ok(@tool.ToolCallOutcome::Complete(@tool.ToolResult::text("ok")))
    },
  )
  let result = parse_result(handle_tools_list(server, @types.RequestId::Int(1)))
  if json_get(result, "tools") is Array(arr) {
    assert_eq(json_field_str(arr[0], "name"), "my_tool")
    assert_eq(json_field_str(arr[0], "description"), "My tool")
  } else {
    panic()
  }
}

///| =====================================================

///| resources/list

///|
/// =====================================================
test "compliance: resources/list returns array with uri and name" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  server.register_resource(
    "file:///test.txt",
    "Test File",
    "A test file",
    "text/plain",
    fn() { Ok({ uri: "file:///test.txt", content: @resource.Text("hello"), }) },
  )
  let result = parse_result(
    handle_resources_list(server, @types.RequestId::Int(1)),
  )
  let resources = json_get(result, "resources")
  assert_eq(json_arr_len(resources), 1)
  if resources is Array(arr) {
    let r = arr[0]
    assert_true(json_has(r, "uri"))
    assert_true(json_has(r, "name"))
  } else {
    panic()
  }
}

///|
test "compliance: resources/list includes mimeType" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  server.register_resource(
    "file:///data.json",
    "Data",
    "JSON data",
    "application/json",
    fn() { Ok({ uri: "file:///data.json", content: @resource.Text("{}"), }) },
  )
  let result = parse_result(
    handle_resources_list(server, @types.RequestId::Int(1)),
  )
  if json_get(result, "resources") is Array(arr) {
    let r = arr[0]
    assert_true(json_has(r, "mimeType"))
    assert_eq(json_field_str(r, "mimeType"), "application/json")
  } else {
    panic()
  }
}

///|
test "compliance: resources/list includes description when present" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  server.register_resource(
    "file:///test.txt",
    "Test",
    "A test resource",
    "text/plain",
    fn() { Ok({ uri: "file:///test.txt", content: @resource.Text("hello"), }) },
  )
  let result = parse_result(
    handle_resources_list(server, @types.RequestId::Int(1)),
  )
  if json_get(result, "resources") is Array(arr) {
    let r = arr[0]
    assert_true(json_has(r, "description"))
  } else {
    panic()
  }
}

///| =====================================================

///| prompts/list

///|
/// =====================================================
test "compliance: prompts/list returns array with name" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  server.register_prompt("greet", "Greeting prompt", [], fn(_args) {
    Ok({
      description: Some("A greeting"),
      messages: [{ role: "user", content: @types.Text("Hello"), }],
    })
  })
  let result = parse_result(
    handle_prompts_list(server, @types.RequestId::Int(1)),
  )
  let prompts = json_get(result, "prompts")
  assert_eq(json_arr_len(prompts), 1)
  if prompts is Array(arr) {
    let p = arr[0]
    assert_true(json_has(p, "name"))
    assert_eq(json_field_str(p, "name"), "greet")
  } else {
    panic()
  }
}

///|
test "compliance: prompts/list includes arguments" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let arg : @types.PromptArgument = {
    name: "name",
    description: Some("Name to greet"),
    required: Some(true),
  }
  server.register_prompt("greet", "Greeting", [arg], fn(_args) {
    Ok({
      description: Some("Greeting"),
      messages: [{ role: "user", content: @types.Text("Hello"), }],
    })
  })
  let result = parse_result(
    handle_prompts_list(server, @types.RequestId::Int(1)),
  )
  if json_get(result, "prompts") is Array(arr) {
    let p = arr[0]
    assert_true(json_has(p, "arguments"))
    let arguments = json_get(p, "arguments")
    assert_eq(json_arr_len(arguments), 1)
    if arguments is Array(arg_arr) {
      let a = arg_arr[0]
      assert_eq(json_field_str(a, "name"), "name")
      assert_true(json_has(a, "description"))
    } else {
      panic()
    }
  } else {
    panic()
  }
}

///|
test "compliance: prompts/list includes description" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  server.register_prompt("greet", "A greeting prompt", [], fn(_args) {
    Ok({
      description: Some("Greeting"),
      messages: [{ role: "user", content: @types.Text("Hello"), }],
    })
  })
  let result = parse_result(
    handle_prompts_list(server, @types.RequestId::Int(1)),
  )
  if json_get(result, "prompts") is Array(arr) {
    let p = arr[0]
    assert_true(json_has(p, "description"))
  } else {
    panic()
  }
}

///| =====================================================

///| Error Handling (via server.handle_request parsing)

///|
/// =====================================================
test "compliance: invalid JSON returns -32700 parse error" {
  let json = @json.parse(
    jsonrpc_error_str(@types.RequestId::Int(0), -32700, "Parse error"),
  ) catch {
    _ => panic()
  }
  let err = json_get(json, "error")
  if err is Object(obj) {
    match obj.get("code") {
      Some(Number(n, ..)) => assert_eq(n.to_int(), -32700)
      _ => panic()
    }
  } else {
    panic()
  }
}

///|
test "compliance: jsonrpc_error format has code and message" {
  let response = jsonrpc_error_str(
    @types.RequestId::Int(1),
    -32601,
    "Method not found",
  )
  let json = @json.parse(response) catch { _ => panic() }
  assert_eq(json_field_str(json, "jsonrpc"), "2.0")
  let err = json_get(json, "error")
  assert_true(json_has(err, "code"))
  assert_true(json_has(err, "message"))
}

///|
test "compliance: jsonrpc_success format has result" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let response = jsonrpc_success_str(
    server,
    @types.RequestId::Int(1),
    Json::object({}),
  )
  let json = @json.parse(response) catch { _ => panic() }
  assert_eq(json_field_str(json, "jsonrpc"), "2.0")
  assert_true(json_has(json, "result"))
  assert_true(!json_has(json, "error"))
}

///|
test "compliance: response _meta carries serverInfo" {
  let server = MCPServer::MCPServer("test-server", "2.0.0")
  let response = handle_tools_list(server, @types.RequestId::Int(1))
  let result = parse_result(response)
  let meta = json_get(result, "_meta")
  let info = json_get(meta, "io.modelcontextprotocol/serverInfo")
  assert_eq(json_field_str(info, "name"), "test-server")
  assert_eq(json_field_str(info, "version"), "2.0.0")
}

///| =====================================================

///| Notification Format

///|
/// =====================================================
test "compliance: tools list_changed notification has correct method" {
  let n = @types.tools_list_changed_notification()
  assert_eq(n.method_name, "notifications/tools/list_changed")
}

///|
test "compliance: resources list_changed notification has correct method" {
  let n = @types.resources_list_changed_notification()
  assert_eq(n.method_name, "notifications/resources/list_changed")
}

///|
test "compliance: prompts list_changed notification has correct method" {
  let n = @types.prompts_list_changed_notification()
  assert_eq(n.method_name, "notifications/prompts/list_changed")
}

///|
test "compliance: notification serializes as valid JSON-RPC notification" {
  let n = @types.tools_list_changed_notification()
  let json_str = n.to_jsonrpc_string()
  let json = @json.parse(json_str) catch { _ => panic() }
  assert_eq(json_field_str(json, "jsonrpc"), "2.0")
  assert_eq(json_field_str(json, "method"), "notifications/tools/list_changed")
  // Notification should NOT have "id" field
  if json is Object(obj) {
    assert_true(obj.get("id") is None)
  } else {
    panic()
  }
}

///| =====================================================

///| JSON-RPC Validation

///|
/// =====================================================
test "compliance: validate_jsonrpc_message accepts valid request" {
  let result = @transport.validate_jsonrpc_message(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
  )
  assert_true(result is Ok(_))
}

///|
test "compliance: validate_jsonrpc_message rejects invalid jsonrpc version" {
  let result = @transport.validate_jsonrpc_message(
    "{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"ping\"}",
  )
  assert_true(result is Err(_))
}

///|
test "compliance: validate_jsonrpc_message rejects non-object" {
  let result = @transport.validate_jsonrpc_message("42")
  assert_true(result is Err(_))
}

///|
test "compliance: validate_jsonrpc_message rejects missing method/result/error" {
  let result = @transport.validate_jsonrpc_message(
    "{\"jsonrpc\":\"2.0\",\"id\":1}",
  )
  assert_true(result is Err(_))
}

///| =====================================================

///| Error Code Compliance (JSON-RPC 2.0)

///|
/// =====================================================
test "compliance: error codes match JSON-RPC 2.0 spec" {
  assert_eq(@types.ParseError("x").to_error_code(), -32700)
  assert_eq(@types.InvalidRequest("x").to_error_code(), -32600)
  assert_eq(@types.MethodNotFound("x").to_error_code(), -32601)
  assert_eq(@types.InvalidParams("x").to_error_code(), -32602)
  assert_eq(@types.InternalError("x").to_error_code(), -32603)
}

///|
test "compliance: tool error uses custom code -32000" {
  assert_eq(@types.ToolError("x").to_error_code(), -32000)
}

///|
test "compliance: spec-defined error codes in -3202x range" {
  assert_eq(@types.HeaderMismatch("x").to_error_code(), -32020)
  assert_eq(
    @types.MissingRequiredClientCapability("x", required=["elicitation"]).to_error_code(),
    -32021,
  )
  assert_eq(
    @types.UnsupportedProtocolVersion(
      "x",
      supported=["2026-07-28"],
      requested="1999-01-01",
    ).to_error_code(),
    -32022,
  )
}

///|
test "compliance: UnsupportedProtocolVersion serializes supported/requested in data" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let err = @types.UnsupportedProtocolVersion(
    "unsupported version",
    supported=["2026-07-28", "2025-11-25"],
    requested="1999-01-01",
  )
  let response = jsonrpc_error_from(@types.RequestId::Int(1), err)
  // Reference `server` so the meta-bearing success builder stays in scope
  // (keeps the test file consistent with the node-2 signature change).
  ignore(server)
  let json = @json.parse(response) catch { _ => panic() }
  let err_obj = json_get(json, "error")
  assert_eq(json_field_str(err_obj, "message"), "unsupported version")
  let data = json_get(err_obj, "data")
  assert_eq(json_field_str(data, "requested"), "1999-01-01")
  // `supported` is a 2-element array of version strings
  let supported = json_get(data, "supported")
  if supported is Array(arr) {
    assert_eq(arr.length(), 2)
  } else {
    panic()
  }
}

///|
test "compliance: MissingRequiredClientCapability serializes requiredCapabilities in data" {
  let err = @types.MissingRequiredClientCapability("needs elicitation", required=[
    "elicitation", "roots",
  ])
  let response = jsonrpc_error_from(@types.RequestId::Int(1), err)
  let json = @json.parse(response) catch { _ => panic() }
  let data = json_get(json_get(json, "error"), "data")
  let required = json_get(data, "requiredCapabilities")
  if required is Array(arr) {
    assert_eq(arr.length(), 2)
  } else {
    panic()
  }
}

///|
test "compliance: HeaderMismatch carries no structured data" {
  let err = @types.HeaderMismatch("Mcp-Name mismatch")
  assert_true(err.to_error_data() is None)
}

///|
#cfg(not(target="wasm-gc"))
async test "mrtr retry: valid requestState passes verification and reaches the tool" {
  let server = MCPServer::MCPServer("test", "1.0.0")
    .with_request_state_codec(
      AesGcmStateCodec::with_key(Bytes::make(32, b'\x42')),
    )
    .with_clock(fn() { 1_700_000_000 })
  // Tool echoes back the _mrtr_responses it received, if any.
  server.register_tool(
    "resume_tool",
    "Resume tool",
    Json::object({ "type": "object" }),
    fn(args) {
      if args is Object(obj) {
        match obj.get("_mrtr_responses") {
          Some(Object(responses)) =>
            if responses.get("login") is Some(_) {
              Ok(
                @tool.ToolCallOutcome::Complete(
                  @tool.ToolResult::text("got-responses"),
                ),
              )
            } else {
              Ok(
                @tool.ToolCallOutcome::Complete(
                  @tool.ToolResult::text("missing-login"),
                ),
              )
            }
          _ =>
            Ok(
              @tool.ToolCallOutcome::Complete(@tool.ToolResult::text("no-resp")),
            )
        }
      } else {
        Ok(@tool.ToolCallOutcome::Complete(@tool.ToolResult::text("bad-args")))
      }
    },
  )
  // Seal a blob bound to the original arguments.
  let arguments = Json::object({ "x": Json::number(1.0) })
  let codec = AesGcmStateCodec::with_key(Bytes::make(32, b'\x42'))
  let blob = codec.seal(
    {
      principal: None,
      expires_at: 1_700_000_000 + 300,
      request_method: "tools/call",
      params_digest: params_digest(arguments),
      state: Json::object({}),
    },
    now=1_700_000_000,
  )
  // Retry request: original params + inputResponses + echoed requestState.
  let retry_params = Json::object({
    "name": Json::string("resume_tool"),
    "arguments": arguments,
    "inputResponses": Json::object({
      "login": Json::object({ "action": Json::string("accept") }),
    }),
    "requestState": Json::string(blob),
  })
  let response = handle_tools_call(
    server,
    @types.RequestId::Int(1),
    retry_params,
  ) catch {
    _ => panic()
  }
  let result = parse_result(response)
  assert_eq(json_field_str(result, "resultType"), "complete")
  match json_get(result, "content") {
    Array(arr) => assert_eq(json_field_str(arr[0], "text"), "got-responses")
    _ => panic()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "mrtr retry: tampered requestState is rejected" {
  let server = MCPServer::MCPServer("test", "1.0.0")
    .with_request_state_codec(
      AesGcmStateCodec::with_key(Bytes::make(32, b'\x42')),
    )
    .with_clock(fn() { 1_700_000_000 })
  let retry_params = Json::object({
    "name": Json::string("any"),
    "arguments": Json::object({}),
    "requestState": Json::string("not-a-valid-blob"),
  })
  let response = handle_tools_call(
    server,
    @types.RequestId::Int(1),
    retry_params,
  ) catch {
    _ => panic()
  }
  let resp_json = @json.parse(response) catch { _ => panic() }
  match json_get(resp_json, "error") {
    Object(_) => () // error response — expected
    _ => panic()
  }
}

///|
test "compliance: notifications/cancelled shape carries requestId and reason" {
  let n = @types.cancelled_notification("42", reason="user asked")
  let json = @json.parse(n.to_jsonrpc_string()) catch { _ => panic() }
  if json is Object(obj) {
    assert_eq(obj.get("method"), Some(Json::string("notifications/cancelled")))
    // Notifications carry no id; the receiver must not respond.
    assert_true(obj.get("id") is None)
    let params = match obj.get("params") {
      Some(Object(p)) => p
      _ => panic()
    }
    assert_eq(params.get("requestId"), Some(Json::string("42")))
    assert_eq(params.get("reason"), Some(Json::string("user asked")))
  } else {
    panic()
  }
}

///|
test "compliance: inbound notification is routed away from the request path" {
  // A message with method but no id is a notification (must not be answered).
  assert_true(
    is_notification_message(
      "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":\"7\"}}",
    ),
  )
  // A request (has id) is not a notification.
  assert_false(
    is_notification_message(
      "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/list\"}",
    ),
  )
  // Malformed JSON is not treated as a notification.
  assert_false(is_notification_message("not json"))
}

///|
fn json_field_int(json : Json, field : String) -> Int {
  if json is Object(obj) {
    match obj.get(field) {
      Some(Number(n, ..)) => n.to_int()
      _ => panic()
    }
  } else {
    panic()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "compliance: unsupported protocol version returns -32022 with data" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0),
    "method": Json::string("tools/list"),
    "params": Json::object({
      "_meta": Json::object({
        "io.modelcontextprotocol/protocolVersion": Json::string("2025-11-25"),
        "io.modelcontextprotocol/clientCapabilities": Json::object({}),
      }),
    }),
  }).stringify()
  let response = server.handle_request(request) catch { _ => panic() }
  let json = @json.parse(response) catch { _ => panic() }
  let err = json_get(json, "error")
  assert_eq(json_field_int(err, "code"), -32022)
  let data = json_get(err, "data")
  assert_eq(json_field_str(data, "requested"), "2025-11-25")
  let supported = json_get(data, "supported")
  if supported is Array(arr) {
    assert_eq(arr.length(), 1)
    assert_eq(arr[0], Json::string("2026-07-28"))
  } else {
    panic()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "compliance: missing protocol version returns -32602" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0),
    "method": Json::string("tools/list"),
    "params": Json::object({
      "_meta": Json::object({
        "io.modelcontextprotocol/clientCapabilities": Json::object({}),
      }),
    }),
  }).stringify()
  let response = server.handle_request(request) catch { _ => panic() }
  let json = @json.parse(response) catch { _ => panic() }
  let err = json_get(json, "error")
  assert_eq(json_field_int(err, "code"), -32602)
  assert_eq(
    json_field_str(err, "message"),
    "Missing required _meta field: io.modelcontextprotocol/protocolVersion",
  )
}

///|
#cfg(not(target="wasm-gc"))
async test "compliance: missing clientCapabilities returns -32602" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0),
    "method": Json::string("tools/list"),
    "params": Json::object({
      "_meta": Json::object({
        "io.modelcontextprotocol/protocolVersion": Json::string(
          @types.ProtocolVersion,
        ),
      }),
    }),
  }).stringify()
  let response = server.handle_request(request) catch { _ => panic() }
  let json = @json.parse(response) catch { _ => panic() }
  let err = json_get(json, "error")
  assert_eq(json_field_int(err, "code"), -32602)
  assert_eq(
    json_field_str(err, "message"),
    "Missing required _meta field: io.modelcontextprotocol/clientCapabilities",
  )
}

///|
#cfg(not(target="wasm-gc"))
async test "compliance: request without _meta at all returns -32602" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0),
    "method": Json::string("tools/list"),
    "params": Json::object({}),
  }).stringify()
  let response = server.handle_request(request) catch { _ => panic() }
  let json = @json.parse(response) catch { _ => panic() }
  let err = json_get(json, "error")
  assert_eq(json_field_int(err, "code"), -32602)
  assert_eq(
    json_field_str(err, "message"),
    "Missing required _meta field: io.modelcontextprotocol/protocolVersion",
  )
}

///|
#cfg(not(target="wasm-gc"))
async test "compliance: request carrying required _meta fields is accepted" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0),
    "method": Json::string("tools/list"),
    "params": Json::object({ "_meta": valid_request_meta() }),
  }).stringify()
  let response = server.handle_request(request) catch { _ => panic() }
  let json = @json.parse(response) catch { _ => panic() }
  assert_true(json_has(json, "result"))
}

///|
#cfg(not(target="wasm-gc"))
async test "compliance: undeclared elicitation capability returns -32021" {
  let server = MCPServer::MCPServer("test", "1.0.0").with_request_state_codec(
    AesGcmStateCodec::with_key(Bytes::make(32, b'\x42')),
  )
  let reqs : Map[String, @types.InputRequestEntry] = Default::default()
  reqs.set("login", {
    method_name: @types.InputRequestKind::ElicitationCreate,
    params: Json::object({ "message": Json::string("Login") }),
  })
  server.register_tool(
    "gate",
    "Gated tool",
    Json::object({ "type": "object" }),
    fn(_args) {
      Ok(
        @tool.ToolCallOutcome::InputRequired(
          input_requests=reqs,
          state=Json::object({}),
        ),
      )
    },
  )
  let params = Json::object({
    "name": Json::string("gate"),
    "arguments": Json::object({}),
  })
  let response = handle_tools_call(server, @types.RequestId::Int(1), params) catch {
    _ => panic()
  }
  let resp_json = @json.parse(response) catch { _ => panic() }
  let err = json_get(resp_json, "error")
  assert_eq(json_field_int(err, "code"), -32021)
  let required = json_get(json_get(err, "data"), "requiredCapabilities")
  if required is Array(arr) {
    assert_eq(arr.length(), 1)
    assert_eq(arr[0], Json::string("elicitation"))
  } else {
    panic()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "compliance: declared elicitation capability allows input_required" {
  let server = MCPServer::MCPServer("test", "1.0.0")
    .with_request_state_codec(
      AesGcmStateCodec::with_key(Bytes::make(32, b'\x42')),
    )
    .with_clock(fn() { 1_700_000_000 })
  let reqs : Map[String, @types.InputRequestEntry] = Default::default()
  reqs.set("login", {
    method_name: @types.InputRequestKind::ElicitationCreate,
    params: Json::object({ "message": Json::string("Login") }),
  })
  server.register_tool(
    "gate",
    "Gated tool",
    Json::object({ "type": "object" }),
    fn(_args) {
      Ok(
        @tool.ToolCallOutcome::InputRequired(
          input_requests=reqs,
          state=Json::object({}),
        ),
      )
    },
  )
  let params = Json::object({
    "name": Json::string("gate"),
    "arguments": Json::object({}),
    "_meta": Json::object({
      "io.modelcontextprotocol/clientCapabilities": Json::object({
        "elicitation": Json::boolean(true),
      }),
    }),
  })
  let response = handle_tools_call(server, @types.RequestId::Int(1), params) catch {
    _ => panic()
  }
  let result = parse_result(response)
  assert_eq(json_field_str(result, "resultType"), "input_required")
  assert_true(json_has(result, "requestState"))
}

///|
#cfg(not(target="wasm-gc"))
async test "mrtr: resources/read input_required → retry → complete" {
  let server = MCPServer::MCPServer("test", "1.0.0")
    .with_request_state_codec(
      AesGcmStateCodec::with_key(Bytes::make(32, b'\x42')),
    )
    .with_clock(fn() { 1_700_000_000 })
    .resource_mrtr("memo://1", "Memo", "A memo resource", "text/plain", fn(
      params,
    ) {
      if params is Object(obj) {
        match obj.get("_mrtr_responses") {
          Some(Object(responses)) =>
            if responses.get("login") is Some(_) {
              Ok(
                @resource.ResourceReadOutcome::Complete({
                  uri: "memo://1",
                  content: @resource.Text("unlocked"),
                }),
              )
            } else {
              Ok(
                @resource.ResourceReadOutcome::Complete({
                  uri: "memo://1",
                  content: @resource.Text("missing"),
                }),
              )
            }
          _ => {
            let reqs : Map[String, @types.InputRequestEntry] = Default::default()
            reqs.set("login", {
              method_name: @types.InputRequestKind::ElicitationCreate,
              params: Json::object({ "message": Json::string("Confirm") }),
            })
            Ok(
              @resource.ResourceReadOutcome::InputRequired(
                input_requests=reqs,
                state=Json::object({}),
              ),
            )
          }
        }
      } else {
        Ok(
          @resource.ResourceReadOutcome::Complete({
            uri: "memo://1",
            content: @resource.Text("bad-params"),
          }),
        )
      }
    })
  let params = Json::object({
    "uri": Json::string("memo://1"),
    "_meta": Json::object({
      "io.modelcontextprotocol/clientCapabilities": Json::object({
        "elicitation": Json::boolean(true),
      }),
    }),
  })
  let first = handle_resources_read(server, @types.RequestId::Int(1), params) catch {
    _ => panic()
  }
  let first_result = parse_result(first)
  assert_eq(json_field_str(first_result, "resultType"), "input_required")
  let blob = json_field_str(first_result, "requestState")
  // Retry with fulfilled input.
  let retry_params = Json::object({
    "uri": Json::string("memo://1"),
    "inputResponses": Json::object({
      "login": Json::object({ "action": Json::string("accept") }),
    }),
    "requestState": Json::string(blob),
    "_meta": Json::object({
      "io.modelcontextprotocol/clientCapabilities": Json::object({
        "elicitation": Json::boolean(true),
      }),
    }),
  })
  let second = handle_resources_read(
    server,
    @types.RequestId::Int(2),
    retry_params,
  ) catch {
    _ => panic()
  }
  let second_result = parse_result(second)
  assert_eq(json_field_str(second_result, "resultType"), "complete")
  let contents = json_get(second_result, "contents")
  if contents is Array(arr) {
    assert_eq(json_field_str(arr[0], "text"), "unlocked")
  } else {
    panic()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "mrtr: prompts/get input_required → retry → complete" {
  let server = MCPServer::MCPServer("test", "1.0.0")
    .with_request_state_codec(
      AesGcmStateCodec::with_key(Bytes::make(32, b'\x42')),
    )
    .with_clock(fn() { 1_700_000_000 })
    .prompt_mrtr("review", "Review prompt", [], fn(params) {
      if params is Object(obj) {
        match obj.get("_mrtr_responses") {
          Some(Object(responses)) =>
            if responses.get("login") is Some(_) {
              Ok(
                @prompt.PromptGetOutcome::Complete({
                  description: None,
                  messages: [{ role: "user", content: @types.Text("ready"), }],
                }),
              )
            } else {
              Ok(
                @prompt.PromptGetOutcome::Complete({
                  description: None,
                  messages: [{ role: "user", content: @types.Text("missing"), }],
                }),
              )
            }
          _ => {
            let reqs : Map[String, @types.InputRequestEntry] = Default::default()
            reqs.set("login", {
              method_name: @types.InputRequestKind::ElicitationCreate,
              params: Json::object({ "message": Json::string("Login") }),
            })
            Ok(
              @prompt.PromptGetOutcome::InputRequired(
                input_requests=reqs,
                state=Json::object({}),
              ),
            )
          }
        }
      } else {
        Ok(
          @prompt.PromptGetOutcome::Complete({
            description: None,
            messages: [{ role: "user", content: @types.Text("bad"), }],
          }),
        )
      }
    })
  let params = Json::object({
    "name": Json::string("review"),
    "arguments": Json::object({}),
    "_meta": Json::object({
      "io.modelcontextprotocol/clientCapabilities": Json::object({
        "elicitation": Json::boolean(true),
      }),
    }),
  })
  let first = handle_prompts_get(server, @types.RequestId::Int(1), params) catch {
    _ => panic()
  }
  let first_result = parse_result(first)
  assert_eq(json_field_str(first_result, "resultType"), "input_required")
  let blob = json_field_str(first_result, "requestState")
  let retry_params = Json::object({
    "name": Json::string("review"),
    "arguments": Json::object({}),
    "inputResponses": Json::object({
      "login": Json::object({ "action": Json::string("accept") }),
    }),
    "requestState": Json::string(blob),
    "_meta": Json::object({
      "io.modelcontextprotocol/clientCapabilities": Json::object({
        "elicitation": Json::boolean(true),
      }),
    }),
  })
  let second = handle_prompts_get(
    server,
    @types.RequestId::Int(2),
    retry_params,
  ) catch {
    _ => panic()
  }
  let second_result = parse_result(second)
  assert_eq(json_field_str(second_result, "resultType"), "complete")
  let messages = json_get(second_result, "messages")
  if messages is Array(arr) {
    assert_eq(json_field_str(json_get(arr[0], "content"), "text"), "ready")
  } else {
    panic()
  }
}

///|
test "compliance: resources/templates/list returns templates and cache fields" {
  let server = MCPServer::MCPServer("test", "1.0.0").resource_template(
    uri_template="memo://{id}",
    name="Memo",
    description="A templated memo",
    mime_type="text/plain",
  )
  let result = parse_result(
    handle_resources_templates_list(server, @types.RequestId::Int(1)),
  )
  assert_eq(json_field_str(result, "cacheScope"), "public")
  assert_eq(json_field_int(result, "ttlMs"), 60000)
  let templates = json_get(result, "resourceTemplates")
  assert_eq(json_arr_len(templates), 1)
  if templates is Array(arr) {
    let t = arr[0]
    assert_eq(json_field_str(t, "uriTemplate"), "memo://{id}")
    assert_eq(json_field_str(t, "name"), "Memo")
    assert_eq(json_field_str(t, "mimeType"), "text/plain")
  } else {
    panic()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "compliance: close_subscription sends graceful result and removes subscription" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let queue : @aqueue.Queue[String] = @aqueue.Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  server.subscriptions.set("42", {
    filter: SubscriptionFilter::empty(),
    reply: queue,
  })
  server.close_subscription("42") catch {
    _ => panic()
  }
  let response = queue.get() catch { _ => panic() }
  let json = @json.parse(response) catch { _ => panic() }
  let result = json_get(json, "result")
  assert_eq(json_field_str(result, "resultType"), "complete")
  let sid_json = json_get(
    json_get(result, "_meta"),
    "io.modelcontextprotocol/subscriptionId",
  )
  match sid_json {
    String(s) => assert_eq(s, "42")
    _ => panic()
  }
  assert_true(server.subscriptions.get("42") is None)
}

///|
#cfg(not(target="wasm-gc"))
async test "compliance: cancelled notification closes matching subscription" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let queue : @aqueue.Queue[String] = @aqueue.Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  server.subscriptions.set("7", {
    filter: SubscriptionFilter::empty(),
    reply: queue,
  })
  let notif = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/cancelled"),
    "params": Json::object({ "requestId": Json::number(7.0) }),
  }).stringify()
  server.handle_inbound_notification(notif) catch {
    _ => panic()
  }
  let response = queue.get() catch { _ => panic() }
  let json = @json.parse(response) catch { _ => panic() }
  let result = json_get(json, "result")
  assert_eq(json_field_str(result, "resultType"), "complete")
  assert_true(server.subscriptions.get("7") is None)
}

///|
test "compliance: list endpoints return deterministic order" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  server.register_tool("zebra", "Zebra", Json::object({}), fn(_args) {
    Ok(@tool.ToolCallOutcome::Complete(@tool.ToolResult::text("z")))
  })
  server.register_tool("alpha", "Alpha", Json::object({}), fn(_args) {
    Ok(@tool.ToolCallOutcome::Complete(@tool.ToolResult::text("a")))
  })
  server.register_resource("file:///z", "Z", "Z resource", "text/plain", fn() {
    Ok({ uri: "file:///z", content: @resource.Text("z"), })
  })
  server.register_resource("file:///a", "A", "A resource", "text/plain", fn() {
    Ok({ uri: "file:///a", content: @resource.Text("a"), })
  })
  server.register_prompt("zebra_prompt", "Z", [], fn(_args) {
    Ok({ description: None, messages: [], })
  })
  server.register_prompt("alpha_prompt", "A", [], fn(_args) {
    Ok({ description: None, messages: [], })
  })
  let server = server
    .resource_template(uri_template="z://{x}", name="Z Template")
    .resource_template(uri_template="a://{x}", name="A Template")
  let tools = json_get(
    parse_result(handle_tools_list(server, @types.RequestId::Int(1))),
    "tools",
  )
  if tools is Array(tarr) {
    assert_eq(json_field_str(tarr[0], "name"), "alpha")
    assert_eq(json_field_str(tarr[1], "name"), "zebra")
  } else {
    panic()
  }
  let resources = json_get(
    parse_result(handle_resources_list(server, @types.RequestId::Int(1))),
    "resources",
  )
  if resources is Array(rarr) {
    assert_eq(json_field_str(rarr[0], "uri"), "file:///a")
    assert_eq(json_field_str(rarr[1], "uri"), "file:///z")
  } else {
    panic()
  }
  let prompts = json_get(
    parse_result(handle_prompts_list(server, @types.RequestId::Int(1))),
    "prompts",
  )
  if prompts is Array(parr) {
    assert_eq(json_field_str(parr[0], "name"), "alpha_prompt")
    assert_eq(json_field_str(parr[1], "name"), "zebra_prompt")
  } else {
    panic()
  }
  let templates = json_get(
    parse_result(
      handle_resources_templates_list(server, @types.RequestId::Int(1)),
    ),
    "resourceTemplates",
  )
  if templates is Array(tarr) {
    assert_eq(json_field_str(tarr[0], "uriTemplate"), "a://{x}")
    assert_eq(json_field_str(tarr[1], "uriTemplate"), "z://{x}")
  } else {
    panic()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "compliance: initialize returns modern-only error naming version" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0),
    "method": Json::string("initialize"),
    "params": Json::object({ "_meta": valid_request_meta() }),
  }).stringify()
  let response = server.handle_request(request) catch { _ => panic() }
  let json = @json.parse(response) catch { _ => panic() }
  let err = json_get(json, "error")
  assert_eq(json_field_int(err, "code"), -32601)
  assert_true(json_field_str(err, "message").contains("2026-07-28"))
}

///|
test "compliance: serverInfo includes description when set" {
  let server = MCPServer::MCPServer("test", "1.0.0").with_description(
    "A compliance test server",
  )
  let result = parse_result(handle_tools_list(server, @types.RequestId::Int(1)))
  let info = json_get(
    json_get(result, "_meta"),
    "io.modelcontextprotocol/serverInfo",
  )
  assert_eq(json_field_str(info, "description"), "A compliance test server")
}

///|
test "compliance: serverInfo omits description when unset" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  let result = parse_result(handle_tools_list(server, @types.RequestId::Int(1)))
  let info = json_get(
    json_get(result, "_meta"),
    "io.modelcontextprotocol/serverInfo",
  )
  assert_false(json_has(info, "description"))
}

///|
#cfg(not(target="wasm-gc"))
async test "compliance: tools/call embedded resource nests contents under resource" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  server.register_tool(
    "embed",
    "Embedded resource tool",
    Json::object({ "type": "object" }),
    fn(_args) {
      Ok(
        @tool.ToolCallOutcome::Complete(
          @tool.ToolResult::success([
            @types.ContentItem::EmbeddedResource(
              @types.EmbeddedResourceContent::Text(
                "memo body",
                uri="memo://1",
                mime_type=Some("text/plain"),
              ),
            ),
            @types.ContentItem::EmbeddedResource(
              @types.EmbeddedResourceContent::Blob(
                "aGk=",
                uri="memo://2",
                mime_type="application/octet-stream",
              ),
            ),
          ]),
        ),
      )
    },
  )
  let params = Json::object({
    "name": Json::string("embed"),
    "arguments": Json::object({}),
  })
  let response = handle_tools_call(server, @types.RequestId::Int(1), params) catch {
    _ => panic()
  }
  let result = parse_result(response)
  let content = json_get(result, "content")
  if content is Array(arr) {
    assert_eq(arr.length(), 2)
    // Text variant: {type:"resource", resource:{uri, text, mimeType?}} —
    // uri/text/mimeType live nested, not flattened onto the item.
    let text_item = arr[0]
    assert_eq(json_field_str(text_item, "type"), "resource")
    assert_false(json_has(text_item, "uri"))
    assert_false(json_has(text_item, "text"))
    let text_res = json_get(text_item, "resource")
    assert_eq(json_field_str(text_res, "uri"), "memo://1")
    assert_eq(json_field_str(text_res, "text"), "memo body")
    assert_eq(json_field_str(text_res, "mimeType"), "text/plain")
    // Blob variant: {type:"resource", resource:{uri, blob, mimeType}}.
    let blob_item = arr[1]
    assert_false(json_has(blob_item, "blob"))
    let blob_res = json_get(blob_item, "resource")
    assert_eq(json_field_str(blob_res, "uri"), "memo://2")
    assert_eq(json_field_str(blob_res, "blob"), "aGk=")
    assert_eq(json_field_str(blob_res, "mimeType"), "application/octet-stream")
  } else {
    panic()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "compliance: prompts/get serializes non-text content without data loss" {
  let server = MCPServer::MCPServer("test", "1.0.0")
  server.register_prompt("mixed", "Mixed content prompt", [], fn(_args) {
    Ok({
      description: None,
      messages: [
        {
          role: "user",
          content: @types.ContentItem::Image("aGk=", mime_type="image/png"),
        },
        { role: "user", content: @types.ContentItem::ResourceLink("memo://1"), },
        {
          role: "assistant",
          content: @types.ContentItem::EmbeddedResource(
            @types.EmbeddedResourceContent::Text(
              "memo body",
              uri="memo://9",
              mime_type=None,
            ),
          ),
        },
      ],
    })
  })
  let params = Json::object({
    "name": Json::string("mixed"),
    "arguments": Json::object({}),
  })
  let response = handle_prompts_get(server, @types.RequestId::Int(1), params) catch {
    _ => panic()
  }
  let result = parse_result(response)
  let messages = json_get(result, "messages")
  if messages is Array(arr) {
    assert_eq(arr.length(), 3)
    // Image content survives (was previously dropped to JSON null).
    let img = json_get(arr[0], "content")
    assert_eq(json_field_str(img, "type"), "image")
    assert_eq(json_field_str(img, "data"), "aGk=")
    assert_eq(json_field_str(img, "mimeType"), "image/png")
    // Resource link survives.
    let link = json_get(arr[1], "content")
    assert_eq(json_field_str(link, "type"), "resource_link")
    assert_eq(json_field_str(link, "uri"), "memo://1")
    // Embedded resource uses the nested wire shape.
    let emb = json_get(arr[2], "content")
    assert_eq(json_field_str(emb, "type"), "resource")
    assert_false(json_has(emb, "text"))
    let emb_res = json_get(emb, "resource")
    assert_eq(json_field_str(emb_res, "uri"), "memo://9")
    assert_eq(json_field_str(emb_res, "text"), "memo body")
  } else {
    panic()
  }
}
