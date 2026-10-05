///|
async test "authenticated MRTR state correlates all response unions before business handlers" {
  let calls = Ref(0)
  let server = MCPServer::MCPServer("test", "1")
    .with_request_state_codec(
      AesGcmStateCodec::with_key(Bytes::make(32, b'\x42')),
    )
    .with_clock(fn() { 1_700_000_000 })
  server.register_tool("confirm", "confirm", { "type": "object" }, (context, _) => {
    calls.val += 1
    match context.continuation_state {
      Some(state) => {
        assert_eq(state, Json::object({ "business": 1 }))
        assert_eq(context.input_responses.length(), 3)
        Ok(@tool.Complete(@tool.ToolResult::text("done")))
      }
      None =>
        Ok(
          @tool.InputRequired(
            input_requests={
              "form": {
                method_name: @types.ElicitationCreate,
                params: {
                  "message": "Age",
                  "requestedSchema": {
                    "type": "object",
                    "properties": {
                      "age": { "type": "integer", "minimum": 18 },
                    },
                    "required": ["age"],
                  },
                },
              },
              "roots": { method_name: @types.RootsList, params: {}, },
              "sample": {
                method_name: @types.SamplingCreateMessage,
                params: { "messages": [], "maxTokens": 1 },
              },
            },
            state={ "business": 1 },
          ),
        )
    }
  })
  let params : Map[String, Json] = {
    "name": "confirm",
    "arguments": {},
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": @types.ProtocolVersion,
      "io.modelcontextprotocol/clientCapabilities": {
        "roots": {},
        "sampling": {},
        "elicitation": { "form": {} },
      },
    },
  }
  let send = fn() {
    Json::object({
      "jsonrpc": "2.0",
      "id": 1,
      "method": "tools/call",
      "params": Json::object(params),
    }).stringify()
  }
  let first = @json.parse(server.handle_request(send()))
  guard first is { "result": { "requestState": String(state), .. }, .. } else {
    fail("expected input_required")
  }
  params["requestState"] = Json::string(state)
  let valid : Map[String, Json] = {
    "form": { "action": "accept", "content": { "age": 18 } },
    "roots": { "roots": [{ "uri": "file:///workspace", "name": "workspace" }] },
    "sample": @types.CreateMessageResult::text("test", "done").to_json(),
  }
  let invalids : Array[Map[String, Json]] = []
  let missing = valid.copy()
  missing.remove("roots")
  invalids.push(missing)
  let extra = valid.copy()
  extra["extra"] = { "roots": [] }
  invalids.push(extra)
  let renamed = valid.copy()
  renamed.remove("roots")
  renamed["wrong"] = { "roots": [] }
  invalids.push(renamed)
  for
    (key, value) in [
      ("form", Json::object({ "action": "accept", "content": { "age": 17 } })),
      ("form", Json::object({ "action": "accept" })),
      ("form", Json::object({ "roots": [] })),
      ("roots", Json::object({ "roots": [{ "uri": "https://example.org" }] })),
      (
        "roots",
        Json::object({ "roots": [{ "uri": "file:///workspace", "name": null }] }),
      ),
      ("sample", Json::object({ "role": "assistant", "model": "test" })),
    ] {
    let changed = valid.copy()
    changed[key] = value
    invalids.push(changed)
  }
  for invalid in invalids {
    params["inputResponses"] = Json::object(invalid)
    guard @json.parse(server.handle_request(send()))
      is { "error": { "code": Number(-32602, ..), .. }, .. } else {
      fail("invalid MRTR response must fail before entering the handler")
    }
  }
  assert_eq(calls.val, 1)
  params["inputResponses"] = Json::object(valid)
  for _ in 0..<2 {
    guard @json.parse(server.handle_request(send()))
      is { "result": { "resultType": String("complete"), .. }, .. } else {
      fail("valid stateless retry must complete")
    }
  }
  assert_eq(calls.val, 3)
}

///|
test "state-only MRTR and unbound input response unions are validated without interpreting business state" {
  let state = sealed_input_state(
    { "mrtrVersion": "business-owned", "inputRequests": false },
    {},
  )
  assert_eq(
    restore_input_state(state, {}),
    Json::object({ "mrtrVersion": "business-owned", "inputRequests": false }),
  )
  for
    valid in [
      Json::object({ "roots": [] }),
      Json::object({ "roots": [], "action": "future-extension" }),
      Json::object({ "action": "cancel" }),
      @types.CreateMessageResult::text("test", "done").to_json(),
    ] {
    @validation.check_unbound_input_response(valid)
  }
  for
    invalid in [
      Json::null(),
      Json::object({}),
      Json::object({ "roots": false }),
      Json::object({ "action": "decline", "content": {} }),
    ] {
    try @validation.check_unbound_input_response(invalid) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("value must be a valid InputResponse union member")
    }
  }
  try restore_input_state(state, { "unexpected": { "roots": [] } }) catch {
    @types.InvalidParams(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("state-only retry cannot carry invented responses")
  }
}

///|
test "MRTR sealing preserves exact numeric form constraints and original business state" {
  let codec = AesGcmStateCodec::with_key(Bytes::make(32, b'\x42'))
  let bound : Json = { "name": "decimal", "arguments": {} }
  let business = @validation.parse_json("0.1000000000000000000000000000001")
  let requests : Map[String, @types.InputRequestEntry] = {
    "form": {
      method_name: @types.ElicitationCreate,
      params: {
        "message": "Amount",
        "requestedSchema": {
          "type": "object",
          "properties": { "amount": { "type": "number", "maximum": business } },
          "required": ["amount"],
        },
      },
    },
  }
  let blob = codec.seal(
    {
      principal: None,
      expires_at: 1000,
      request_method: "tools/call",
      params_digest: params_digest(bound),
      state: sealed_input_state(business, requests),
    },
    now=0,
  )
  let restored = codec
    .open(
      blob,
      { principal: None, request_method: "tools/call", params: bound, },
      now=1,
    )
    .unwrap()
  let valid : Map[String, Json] = {
    "form": { "action": "accept", "content": { "amount": business } },
  }
  assert_eq(
    restore_input_state(restored.state, valid).stringify(),
    "0.1000000000000000000000000000001",
  )
  let invalid : Map[String, Json] = {
    "form": @validation.parse_json(
      "{\"action\":\"accept\",\"content\":{\"amount\":0.1000000000000000000000000000002}}",
    ),
  }
  try restore_input_state(restored.state, invalid) catch {
    @types.InvalidParams(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("authenticated constraint must not be rounded")
  }
}
