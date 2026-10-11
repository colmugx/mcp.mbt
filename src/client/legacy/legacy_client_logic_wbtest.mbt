// LegacyClient pure-logic test. The dummy transport is an HttpClient one that
// is only constructed, never sent on (safe on js too); wasm-gc has no
// HttpClientTransport and is gated out by moon.pkg targets.

///|
test "next_request_id increments" {
  let client = LegacyClient::LegacyClient(
    name="test",
    version="0.0.1",
    transport=@transport.AnyTransport::HttpClient(
      @transport.HttpClientTransport::HttpClientTransport(
        "http://unused.invalid",
      ),
    ),
  )
  @debug.assert_eq(client.next_request_id(), 1)
  @debug.assert_eq(client.next_request_id(), 2)
}
