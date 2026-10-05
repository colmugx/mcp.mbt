///|
/// Handler-authored MRTR requests are server output: reject invalid wire
/// shapes before issuing continuation state or asking the client to act.
fn validate_generated_input(
  entry : @types.InputRequestEntry,
) -> Unit raise @types.MCPError {
  match entry.method_name {
    @types.ElicitationCreate =>
      ignore(@validation.ElicitationValidator::compile(entry.params))
    @types.SamplingCreateMessage =>
      ignore(@types.CreateMessageRequest::from_json(entry.params))
    @types.RootsList => @validation.check_roots_request(entry.params)
  }
}
