// cancel_request transport-branch tests (A9a) — native+wasm only: they need a
// Stdio-backed transport (js StdioTransport stub aborts; wasm-gc has none).

///|
async test "cancel_request on stdio client takes the send path" {
  // An unstarted StdioClientTransport still proves the branch: the send is
  // attempted (transport error surfaces as "Failed to send cancellation")
  // rather than rejected as unsupported.
  let transport = @transport.AnyTransport::StdioClient(
    @transport.StdioClientTransport::StdioClientTransport(cmd="cat"),
  )
  let client = MCPClient::MCPClient(name="t", version="1", transport~)
  try client.cancel_request(@types.RequestId::Int(5), reason="test") catch {
    @types.InternalError(msg) =>
      assert_true(msg.contains("Failed to send cancellation"))
    _ => panic()
  } noraise {
    _ => panic()
  }
}

///|
async test "cancel_request on non-client stdio transport is unsupported" {
  // The server-side Stdio transport is not a client channel: no
  // notifications/cancelled may be sent on it.
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::StdioTransport(),
  )
  let client = MCPClient::MCPClient(name="t", version="1", transport~)
  try client.cancel_request(@types.RequestId::Int(5)) catch {
    @types.InternalError(msg) =>
      assert_true(msg.contains("not supported for this transport"))
    _ => panic()
  } noraise {
    _ => panic()
  }
}
