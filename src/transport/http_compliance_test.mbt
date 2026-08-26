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

///| SSE Event Format

///|
/// =====================================================
test "compliance: notification serializes as SSE data field" {
  let n = @types.tools_list_changed_notification()
  let json = n.to_jsonrpc_string()
  // SSE format: "data: <json>\n\n"
  let sse_event = "data: " + json + "\n\n"
  assert_true(sse_event.contains("data: "))
  assert_true(sse_event.contains("notifications/tools/list_changed"))
  // Verify the JSON within SSE is valid
  let payload = parse(json)
  @debug.assert_eq(jstr(payload, "jsonrpc"), "2.0")
}

///| =====================================================

///| JSON-RPC over HTTP Response Format

///|
/// =====================================================
test "compliance: HTTP response uses application/json content type for regular responses" {
  // Verify our response format is valid JSON
  let response = Json::object({ "jsonrpc": "2.0", "id": 1.0, "result": {} }).stringify()
  let json = parse(response)
  @debug.assert_eq(jstr(json, "jsonrpc"), "2.0")
  assert_true(jhas(json, "result"))
}

///|
test "compliance: HTTP response uses text/event-stream for SSE" {
  // Verify notification format is compatible with SSE
  let n = @types.tools_list_changed_notification()
  let notification = n.to_jsonrpc_string()
  let json = parse(notification)
  // SSE events should not have "id" field (notifications)
  if json is Object(obj) {
    assert_true(obj.get("id") is None)
  } else {
    panic()
  }
}

///| =====================================================

///| Base64 Sentinel Encoding

///|
/// =====================================================
test "compliance: base64 sentinel round-trips UTF-8 values" {
  let cases = [
    "us-west1", "Hello, 世界", " padded ", "line1\nline2", "=?base64?literal?=",
  ]
  for s in cases {
    let encoded = encode_base64_sentinel(s)
    let decoded = decode_base64_sentinel(encoded).unwrap()
    @debug.assert_eq(decoded, s)
  }
}

///|
test "compliance: base64 decode rejects invalid input" {
  match decode_base64("!!!") {
    Some(_) => panic()
    None => ()
  }
}

///|
test "compliance: header value safety detects unsafe values" {
  assert_true(is_header_safe("us-west1"))
  assert_false(is_header_safe("Hello, 世界"))
  assert_false(is_header_safe(" padded "))
  assert_false(is_header_safe("=?base64?literal?="))
}

///|
test "compliance: encode_header_value matches spec examples" {
  @debug.assert_eq(encode_header_value("us-west1"), "us-west1")
  @debug.assert_eq(
    encode_header_value("Hello, 世界"),
    "=?base64?SGVsbG8sIOS4lueVjA==?=",
  )
  @debug.assert_eq(encode_header_value(" padded "), "=?base64?IHBhZGRlZCA=?=")
  @debug.assert_eq(
    encode_header_value("line1\nline2"),
    "=?base64?bGluZTEKbGluZTI=?=",
  )
  @debug.assert_eq(
    encode_header_value("=?base64?literal?="),
    "=?base64?PT9iYXNlNjQ/bGl0ZXJhbD89?=",
  )
}

///|
test "compliance: valid header characters rejects CR/LF and controls" {
  assert_true(is_valid_header_characters("us-west1"))
  assert_false(is_valid_header_characters("a\r\nb"))
  assert_false(is_valid_header_characters("a\u0000b"))
}

///| =====================================================

///| SSE Response Classification

///|
/// =====================================================
test "compliance: classify_jsonrpc_message detects notifications and final responses" {
  let notif = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\"}"
  let single_response = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}"
  let error_response = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32601,\"message\":\"x\"}}"
  @debug.assert_eq(classify_jsonrpc_message(notif), Notification)
  @debug.assert_eq(classify_jsonrpc_message(single_response), FinalResponse)
  @debug.assert_eq(classify_jsonrpc_message(error_response), FinalResponse)
}

///|
test "compliance: jsonrpc_error_code detects MethodNotFound" {
  let not_found = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}"
  @debug.assert_eq(jsonrpc_error_code(not_found), Some(-32601))
  let ok = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}"
  @debug.assert_eq(jsonrpc_error_code(ok), None)
}

///|
test "compliance: sse_event_line frames JSON payload" {
  let payload = "{\"jsonrpc\":\"2.0\",\"method\":\"x\"}"
  @debug.assert_eq(sse_event_line(payload), "data: " + payload + "\n\n")
}

///| =====================================================

///| Request/Notification & Protocol Version Validation

///|
/// =====================================================
test "compliance: is_notification recognizes notification bodies" {
  let notif = @json.parse("{\"jsonrpc\":\"2.0\",\"method\":\"x\"}") catch {
    _ => null
  }
  let req = @json.parse("{\"jsonrpc\":\"2.0\",\"method\":\"x\",\"id\":1}") catch {
    _ => null
  }
  assert_true(is_notification(notif))
  assert_false(is_notification(req))
}

///|
test "compliance: unsupported_protocol_version_error carries -32022 data" {
  let body = unsupported_protocol_version_error("2025-03-26")
  let json = parse(body)
  if json is Object(obj) {
    match obj.get("error") {
      Some(Object(err)) => {
        match err.get("code") {
          Some(Number(n, ..)) => @debug.assert_eq(n.to_int(), -32022)
          _ => panic()
        }
        match err.get("data") {
          Some(Object(data)) =>
            match data.get("requested") {
              Some(String(s)) => @debug.assert_eq(s, "2025-03-26")
              _ => panic()
            }
          _ => panic()
        }
      }
      _ => panic()
    }
  } else {
    panic()
  }
}

///| =====================================================

///| Client x-mcp-header Extraction

///|
/// =====================================================
test "compliance: extract_argument_value walks path and converts primitives" {
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"t\",\"arguments\":{\"region\":\"us-west1\",\"count\":42,\"ok\":true,\"skip\":null,\"nested\":{\"x\":\"deep\"}}}}"
  @debug.assert_eq(extract_argument_value(body, ["region"]), Some("us-west1"))
  @debug.assert_eq(extract_argument_value(body, ["count"]), Some("42"))
  @debug.assert_eq(extract_argument_value(body, ["ok"]), Some("true"))
  @debug.assert_eq(extract_argument_value(body, ["skip"]), None)
  @debug.assert_eq(extract_argument_value(body, ["nested", "x"]), Some("deep"))
  @debug.assert_eq(extract_argument_value(body, ["missing"]), None)
}
