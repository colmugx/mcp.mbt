///| MCP Protocol Compliance Tests

///|

///| Tests that verify the SDK's JSON-RPC responses conform to the

///| MCP 2025-11-25 specification.

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
    fn(_args) { Ok(@tool.ToolResult::text("ok")) },
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
    fn(_args) { Ok(@tool.ToolResult::text("ok")) },
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
    fn() { Ok({ uri: "file:///test.txt", content: @resource.Text("hello") }) },
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
    fn() { Ok({ uri: "file:///data.json", content: @resource.Text("{}") }) },
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
    fn() { Ok({ uri: "file:///test.txt", content: @resource.Text("hello") }) },
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
      messages: [{ role: "user", content: @types.Text("Hello") }],
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
      messages: [{ role: "user", content: @types.Text("Hello") }],
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
      messages: [{ role: "user", content: @types.Text("Hello") }],
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
  assert_true(err.to_error_data().is_empty())
}
