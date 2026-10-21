///|
fn http_peer_error(
  body : String,
  expected : @types.RequestId,
) -> @types.MCPError raise @types.MCPError {
  let value = @validation.parse_json(body)
  guard value is Object(fields) &&
    fields.get("jsonrpc") == Some(Json::string("2.0")) &&
    !fields.contains("method") &&
    !fields.contains("result") &&
    fields.get("id") is Some(id) &&
    @types.RequestId::from_json(id) == expected &&
    fields.get("error") is Some(error) else {
    raise @types.InvalidRequest(
      "HTTP error response must match the originating JSON-RPC request",
    )
  }
  @types.MCPError::from_jsonrpc_error(error)
}
