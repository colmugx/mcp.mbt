///|
/// Fetch discovery without discarding cache hints, instructions or open metadata.
pub async fn MCPClient::discover_result(
  self : MCPClient,
) -> @types.DiscoverResult {
  let id = self.next_request_id()
  let request = build_discover_request_json(id, self.request_meta())
  let value = match self.backend {
    Modern =>
      parse_jsonrpc_response_decoded(
        self.send_request_decoded_json(request, @types.RequestId::Int(id)).parsed,
      )
    Legacy(legacy) =>
      parse_jsonrpc_response(
        legacy.send_raw(
          apply_legacy_meta_to_request(request.stringify(), build_legacy_meta()),
        ),
      )
  }
  let result = @types.DiscoverResult::from_json(value)
  self.server_capabilities = Some(result.capabilities)
  self.server_info = parse_server_info_from_result(value)
  result
}
