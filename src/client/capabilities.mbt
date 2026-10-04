///|
/// Configure explicit capabilities after registering the corresponding handlers.
/// Advertising input support without its handler is rejected before any request.
pub fn MCPClient::with_capabilities(
  self : MCPClient,
  capabilities : @types.ClientCapabilities,
) -> MCPClient raise @types.MCPError {
  let capabilities = @types.ClientCapabilities::from_json(
    capabilities.to_json(),
  )
  if capabilities.roots is Some(_) && self.roots_handler is None {
    raise @types.InvalidParams("roots capability requires an on_roots handler")
  }
  if capabilities.sampling is Some(_) && self.sampling_handler is None {
    raise @types.InvalidParams(
      "sampling capability requires an on_sampling handler",
    )
  }
  if capabilities.elicitation is Some(_) && self.elicitation_handler is None {
    raise @types.InvalidParams(
      "elicitation capability requires an on_elicitation handler",
    )
  }
  { ..self, capabilities, }
}
