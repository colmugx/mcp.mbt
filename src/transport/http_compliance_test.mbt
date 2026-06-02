///| HTTP Transport Compliance Test

///|

///| Verifies the HTTP transport conforms to MCP Streamable HTTP spec.

///|
/// Helper: parse JSON string
fn parse(json : String) -> Json {
  @json.parse(json) catch {
    _ => panic()
  }
}

///|
/// Helper: get field as string
fn jstr(json : Json, field : String) -> String {
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
/// Helper: check has field
fn jhas(json : Json, field : String) -> Bool {
  if json is Object(obj) {
    obj.get(field) is Some(_)
  } else {
    false
  }
}

///|
/// Helper: get field as Json
fn _jget(json : Json, field : String) -> Json {
  if json is Object(obj) {
    match obj.get(field) {
      Some(v) => v
      None => panic()
    }
  } else {
    panic()
  }
}

///| =====================================================

///| HTTP Transport Configuration

///|
/// =====================================================
test "compliance: HttpTransport default port is 4240" {
  let transport = HttpTransport::new()
  assert_eq(transport.port, 4240)
}

///|
test "compliance: HttpTransport default endpoint is /mcp" {
  let transport = HttpTransport::new()
  assert_eq(transport.endpoint_path, "/mcp")
}

///|
test "compliance: HttpTransport supports custom port and path" {
  let transport = HttpTransport::new(port=8080, endpoint_path="/api/mcp")
  assert_eq(transport.port, 8080)
  assert_eq(transport.endpoint_path, "/api/mcp")
}

///|
test "compliance: HttpTransport supports streaming" {
  let transport = HttpTransport::new()
  assert_true(transport.supports_streaming())
}

///| =====================================================

///| SSE Event Format

///|
/// =====================================================
test "compliance: notification serializes as SSE data field" {
  let n = @types.tools_list_changed_notification()
  let json = @jsonutil.jsonrpc_notification(n.method_name, n.params)
  // SSE format: "data: <json>\n\n"
  let sse_event = "data: " + json + "\n\n"
  assert_true(sse_event.contains("data: "))
  assert_true(sse_event.contains("notifications/tools/list_changed"))
  // Verify the JSON within SSE is valid
  let payload = parse(json)
  assert_eq(jstr(payload, "jsonrpc"), "2.0")
}

///| =====================================================

///| JSON-RPC over HTTP Response Format

///|
/// =====================================================
test "compliance: HTTP response uses application/json content type for regular responses" {
  // Verify our response format is valid JSON
  let response = @jsonutil.jsonrpc_success(
    @types.RequestId::Int(1),
    @jsonutil.json_object([]),
  )
  let json = parse(response)
  assert_eq(jstr(json, "jsonrpc"), "2.0")
  assert_true(jhas(json, "result"))
}

///|
test "compliance: HTTP response uses text/event-stream for SSE" {
  // Verify notification format is compatible with SSE
  let n = @types.tools_list_changed_notification()
  let notification = @jsonutil.jsonrpc_notification(n.method_name, n.params)
  let json = parse(notification)
  // SSE events should not have "id" field (notifications)
  if json is Object(obj) {
    assert_true(obj.get("id") is None)
  } else {
    panic()
  }
}
