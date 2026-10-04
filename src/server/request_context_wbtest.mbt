///|
fn runtime_request(
  id : Int,
  name : String,
  arguments : Json,
  state? : String,
  responses? : Json,
) -> String {
  let params : Map[String, Json] = {
    "name": Json::string(name),
    "arguments": arguments,
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": { "roots": {} },
      "trace": "kept",
    },
  }
  if state is Some(state) {
    params.set("requestState", Json::string(state))
  }
  if responses is Some(responses) {
    params.set("inputResponses", responses)
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": Json::number(id.to_double()),
    "method": "tools/call",
    "params": Json::object(params),
  }).stringify()
}

///|
async test "MRTR context restores state and binds principal tool name and arguments" {
  let now = Ref(1_700_000_000)
  let calls = Ref(0)
  let codec = AesGcmStateCodec::with_key(Bytes::make(32, b'\x42'))
  let server = MCPServer::MCPServer("test", "1")
    .with_request_state_codec(codec)
    .with_clock(fn() { now.val })
  server.registry.register_definition(
    @types.ToolDefinition::new("resume", {
      "type": "object",
      "additionalProperties": false,
    }),
    (context, arguments) => {
      calls.val += 1
      assert_eq(arguments, Json::object({}))
      assert_eq(context.meta.get("trace"), Some(Json::string("kept")))
      assert_eq(context.principal.map(fn(p) { p.id }), Some("alice"))
      if context.continuation_state is Some(state) {
        assert_eq(state, Json::object({ "step": 2 }))
        assert_true(context.input_responses.contains("roots"))
        Ok(@tool.Complete(@tool.ToolResult::text("resumed")))
      } else {
        Ok(
          @tool.InputRequired(
            input_requests={
              "roots": { method_name: @types.RootsList, params: {}, },
            },
            state={ "step": 2 },
          ),
        )
      }
    },
  )
  let alice = @runtime.Principal::new("alice")
  let first = @json.parse(
    server.handle_request(runtime_request(1, "resume", {}), principal=alice),
  )
  guard first is { "result": { "requestState": String(blob), .. }, .. } else {
    fail("expected requestState")
  }
  let original = Json::object({})
  let responses : Json = { "roots": { "resultType": "complete", "roots": [] } }
  let retry = runtime_request(2, "resume", original, state=blob, responses~)
  for _ in 0..<2 {
    let completed = @json.parse(server.handle_request(retry, principal=alice))
    guard completed
      is { "result": { "resultType": String("complete"), .. }, .. } else {
      fail("valid stateless retry must complete")
    }
  }
  assert_eq(original, Json::object({}))
  assert_eq(calls.val, 3)
  for
    request in [
      runtime_request(3, "another-tool", {}, state=blob, responses~),
      runtime_request(
        4,
        "resume",
        { "different": true },
        state=blob,
        responses~,
      ),
    ] {
    let rejected = @json.parse(server.handle_request(request, principal=alice))
    guard rejected is { "error": { "code": Number(-32602, ..), .. }, .. } else {
      fail("cross-operation state must be rejected")
    }
  }
  let other = @json.parse(
    server.handle_request(retry, principal=@runtime.Principal::new("bob")),
  )
  guard other is { "error": { "code": Number(-32602, ..), .. }, .. } else {
    fail("principal mismatch must be rejected")
  }
  now.val += 306
  let expired = @json.parse(server.handle_request(retry, principal=alice))
  guard expired is { "error": { "code": Number(-32602, ..), .. }, .. } else {
    fail("expired state must be rejected")
  }
  assert_eq(calls.val, 3)
}

///|
async test "missing tool arguments are empty and malformed MRTR fields never reach handlers" {
  let calls = Ref(0)
  let server = MCPServer::MCPServer("test", "1").tool(
    "empty",
    "Empty",
    { "type": "object" },
    (_, arguments) => {
      calls.val += 1
      assert_eq(arguments, Json::object({}))
      Ok(@tool.ToolResult::text("ok"))
    },
  )
  let params : Map[String, Json] = {
    "name": "empty",
    "_meta": valid_request_meta(),
  }
  let wire = fn() {
    Json::object({
      "jsonrpc": "2.0",
      "id": 1,
      "method": "tools/call",
      "params": Json::object(params),
    }).stringify()
  }
  let result = @json.parse(server.handle_request(wire()))
  guard result is { "result": { "resultType": String("complete"), .. }, .. } else {
    fail("omitted arguments must be allowed")
  }
  for
    (key, value) in [
      ("requestState", Json::null()),
      ("inputResponses", Json::array([])),
      ("arguments", Json::null()),
    ] {
    params.set(key, value)
    let result = @json.parse(server.handle_request(wire()))
    guard result is { "error": { "code": Number(-32602, ..), .. }, .. } else {
      fail("malformed params must fail before execution")
    }
    params.remove(key)
  }
  assert_eq(calls.val, 1)
}

///|
test "default MRTR clock uses real wall time" {
  let server = MCPServer::MCPServer("test", "1")
  let expected = (@async.now() / 1000).to_int()
  let actual = (server.clock)()
  assert_true(actual >= expected && actual <= expected + 1)
  assert_true(actual > 1_700_000_000)
}
