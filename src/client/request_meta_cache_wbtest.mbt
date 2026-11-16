///|
test "client request metadata cache matches uncached builder and wire" {
  let client = MCPClient::MCPClient(
    name="client-identity",
    version="2.0",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  )
  let reference = build_request_meta(
    client.client_name, client.client_version, client.capabilities,
  )
  assert_eq(client.request_meta(), reference)
  let before = client.request_meta().stringify()
  for id in 1..<25 {
    let request = build_tools_call_request(
      id,
      "echo",
      client.request_meta(),
      arguments="{\"message\":\"hi\"}",
      progress_token=@types.ProgressToken::String("same-progress"),
    )
    guard @validation.parse_json(request)
      is {
        "params": { "_meta": { "progressToken": String("same-progress"), .. }, .. },
        ..
      } else {
      fail("missing progressToken in tool request")
    }
  }
  // Adding progressToken to a request must not pollute subsequent requests.
  assert_eq(client.request_meta().stringify(), before)
  assert_eq(client.request_meta(), reference)
}

///|
test "client metadata snapshots update on capability builders without altering original" {
  let client = MCPClient::MCPClient(
    name="x",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  )
  let original = client.request_meta().stringify()
  let with_handlers = client
    .on_roots(fn() { Ok([]) })
    .on_sampling(fn(_) { Err(@types.InternalError("not used")) })
    .on_elicitation(fn(_) { Err(@types.InternalError("not used")) })
  assert_eq(
    with_handlers.request_meta(),
    build_request_meta("x", "1", with_handlers.capabilities),
  )
  assert_eq(client.request_meta().stringify(), original)
  guard with_handlers.request_meta()
    is {
      "io.modelcontextprotocol/clientCapabilities": {
        "roots": { .. }, "sampling": { .. }, "elicitation": { "form": { .. }, .. },
        ..
      },
      ..
    } else {
    fail("capability builders did not invalidate metadata cache")
  }
  let configured = with_handlers.with_capabilities(
    @types.ClientCapabilities::new(
      extensions={ "example.org/feature": { "revision": 2 } },
    ),
  )
  assert_eq(
    configured.request_meta(),
    build_request_meta("x", "1", configured.capabilities),
  )
  assert_eq(with_handlers.request_meta(),
    build_request_meta("x", "1", with_handlers.capabilities))
  assert_eq(client.request_meta().stringify(), original)
}

///|
test "client log-level metadata is per-request and does not mutate cached data" {
  let client = MCPClient::MCPClient(
    name="logging-client",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  )
  let original = client.request_meta().stringify()
  assert_eq(
    client.request_meta(log_level=Some("debug")),
    build_request_meta("logging-client", "1", client.capabilities,
      log_level=Some("debug")),
  )
  assert_eq(client.request_meta().stringify(), original)
}

///|
test "tool request without progress token preserves cached metadata without mutation" {
  let client = MCPClient::MCPClient(
    name="no-progress-client",
    version="1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  )
  let meta = client.request_meta()
  let before = meta.stringify()
  let request = @validation.parse_json(
    build_tools_call_request(
      1,
      "echo",
      meta,
      arguments="{\"message\":\"hi\"}",
    ),
  )
  guard request is { "params": { "_meta": wire_meta, .. }, .. } else {
    fail("tool request must contain request metadata")
  }
  assert_eq(wire_meta, meta)
  assert_eq(meta.stringify(), before)
  assert_eq(client.request_meta().stringify(), before)
}
