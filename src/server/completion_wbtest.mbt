///|
async test "completion advertises enabled registry and passes context and resolved arguments" {
  let registry = CompletionRegistry::new().register(
    @types.CompletionReference::resource("memo://{id}"),
    (context, params) => {
      assert_eq(context.principal.map(fn(p) { p.id }), Some("alice"))
      assert_eq(params.argument.name, "id")
      assert_eq(params.argument.value, "a")
      assert_eq(
        params.context.unwrap().arguments.unwrap().get("locale"),
        Some("zh"),
      )
      Ok(
        @types.CompletionResult::new(["alpha"], total=2, has_more=true, metadata={
          ..@types.ResultMetadata::empty(),
          meta: Some({ "trace": "kept" }),
        }),
      )
    },
  )
  let server = MCPServer::MCPServer("test", "1").with_completions(registry)
  let discovered = @json.parse(
    handle_discover(server, @types.RequestId::Int(1)),
  )
  guard discovered
    is {
      "result": { "capabilities": { "completions": Object(_), .. }, .. },
      ..
    } else {
    fail("enabled completion registry must advertise capability")
  }
  let params = @types.CompleteRequestParams::new(
    @types.CompletionReference::resource("memo://{id}"),
    @types.CompletionArgument::new("id", "a"),
    context=@types.CompletionContext::new(arguments={ "locale": "zh" }),
    meta={
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": {},
    },
  )
  let wire = Json::object({
    "jsonrpc": "2.0",
    "id": 2,
    "method": "completion/complete",
    "params": params.to_json(),
  }).stringify()
  let response = @json.parse(
    server.handle_request(wire, principal=@runtime.Principal::new("alice")),
  )
  guard response is { "result": result, .. } else {
    fail("expected completion result")
  }
  let result = @types.CompletionResult::from_json(result)
  assert_eq(result.values, ["alpha"])
  assert_eq(result.has_more, Some(true))
  assert_eq(
    result.metadata.meta.unwrap().get("trace"),
    Some(Json::string("kept")),
  )
}

///|
async test "disabled completions returns method not found while enabled empty registry returns empty values" {
  let server = MCPServer::MCPServer("test", "1")
  let params : Json = {
    "ref": { "type": "ref/prompt", "name": "unknown" },
    "argument": { "name": "id", "value": "a" },
  }
  let context = @runtime.RequestContext::new(@types.RequestId::Int(1))
  let disabled = @json.parse(handle_completion(server, context, params))
  guard disabled is { "error": { "code": Number(-32601, ..), .. }, .. } else {
    fail("disabled capability must reject method")
  }
  let enabled = server.with_completions(CompletionRegistry::new())
  let result = @json.parse(handle_completion(enabled, context, params))
  guard result
    is { "result": { "completion": { "values": Array(values), .. }, .. }, .. } else {
    fail("enabled registry must support the method")
  }
  assert_true(values.is_empty())
  let bad = @json.parse(
    handle_completion(enabled, context, {
      "ref": { "type": "unknown" },
      "argument": {},
    }),
  )
  guard bad is { "error": { "code": Number(-32602, ..), .. }, .. } else {
    fail("malformed completion must be invalid params")
  }
}
