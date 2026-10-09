///|
/// Decode a peer error without collapsing its code or data to InternalError.
pub fn MCPError::from_jsonrpc_error(value : Json) -> MCPError raise MCPError {
  let fields = wire_object(value)
  let code = match fields.get("code") {
    Some(value) => JsonInteger::from_json(value)
    None => raise InvalidRequest("Missing JSON-RPC error code")
  }
  let message = wire_string(fields, "message")
  RemoteError(
    message,
    code~,
    data=fields.get("data"),
    extensions=wire_extensions(fields, ["code", "message", "data"]),
  )
}

///|
pub fn MCPError::to_jsonrpc_error(self : MCPError) -> Json {
  let fields = match self {
    RemoteError(_, extensions~, ..) =>
      wire_extensions(extensions, ["code", "message", "data"])
    _ => Map([])
  }
  fields.set("code", self.to_error_code().to_json())
  fields.set("message", Json::string(self.message()))
  match self.to_error_data() {
    Some(value) => fields.set("data", value)
    None => ()
  }
  Json::object(fields)
}
