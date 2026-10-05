///|
test "server MRTR rejects malformed input requests as server errors rather than capability errors" {
  for
    entry in [
      @types.InputRequestEntry::{
        method_name: @types.ElicitationCreate,
        params: { "message": "name", "requestedSchema": { "type": "object" } },
      },
      @types.InputRequestEntry::{
        method_name: @types.ElicitationCreate,
        params: {
          "message": "name",
          "requestedSchema": {
            "type": "object",
            "properties": { "name": { "type": "string", "$dynamicRef": "#a" } },
          },
        },
      },
      @types.InputRequestEntry::{
        method_name: @types.SamplingCreateMessage,
        params: { "messages": [], "maxTokens": "1" },
      },
      @types.InputRequestEntry::{ method_name: @types.RootsList, params: null, },
    ] {
    let requests : Map[String, @types.InputRequestEntry] = { "bad": entry }
    match check_required_capabilities(capability_test_params({}), requests) {
      Some(@types.InternalError(message)) =>
        assert_true(message.contains("bad"))
      _ => fail("malformed server request must not be emitted")
    }
  }
}

///|
async test "tools input_required validates handler-authored requests before sealing state" {
  let server = MCPServer::MCPServer("test", "1")
  server.register_tool("input", "input", { "type": "object" }, fn(_, _) {
    Ok(
      @tool.InputRequired(
        input_requests={
          "bad": {
            method_name: @types.ElicitationCreate,
            params: { "message": "name" },
          },
        },
        state={},
      ),
    )
  })
  let response = handle_tools_call(
    server,
    @runtime.RequestContext::new(@types.RequestId::Int(1)),
    { "name": "input", "arguments": {} },
  )
  guard @json.parse(response)
    is {
      "error": { "code": Number(-32603, ..), "message": String(message), .. },
      ..
    } else {
    fail("invalid generated request must produce an InternalError")
  }
  assert_true(message.contains("Invalid server input request 'bad'"))
  assert_false(message.contains("codec"))
}
