// LegacyClient tests that construct a Stdio-backed transport. Gated to
// native+wasm: the StdioTransport stub aborts on js / wasm-gc.

///|
#cfg(any(target="native", target="wasm"))
test "next_request_id increments" {
  let client = LegacyClient::LegacyClient(
    name="test",
    version="0.0.1",
    transport=@transport.AnyTransport::Stdio(
      @transport.StdioTransport::StdioTransport(),
    ),
  )
  @debug.assert_eq(client.next_request_id(), 1)
  @debug.assert_eq(client.next_request_id(), 2)
}
