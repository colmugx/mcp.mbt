///|
/// Fetch discovery without discarding cache hints, instructions or open metadata.
pub async fn MCPClient::discover_result(
  self : MCPClient,
) -> Result[@types.DiscoverResult, @types.MCPError] {
  let request = build_discover_request(
    self.next_request_id(),
    self.request_meta(),
  )
  let response = match self.backend {
    Modern => self.send_request(request)
    Legacy(legacy) =>
      legacy.send_raw(
        apply_legacy_meta_to_request(request, build_legacy_meta()),
      )
  }
  let response = match response {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let value = match parse_jsonrpc_response(response) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let result = @types.DiscoverResult::from_json(value) catch {
    error => return Err(error)
  }
  self.server_capabilities = Some(result.capabilities)
  self.server_info = parse_server_info_from_result(value)
  Ok(result)
}
