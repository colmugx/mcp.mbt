///|
/// Validate the response against the tool-selection policy of its request.
pub fn check_sampling_response(
  request : Json,
  response : Json,
) -> Unit raise @types.MCPError {
  let request = @types.CreateMessageRequest::from_json(request)
  let response = @types.CreateMessageResult::from_json(response)
  let has_tool_use = match response.content {
    Single(ToolUse(_)) => true
    Multiple(blocks) => blocks.any(block => block is ToolUse(_))
    _ => false
  }
  match request.tool_choice {
    Some({ mode: Some(Required), .. }) if !has_tool_use =>
      raise @types.InvalidParams(
        "Sampling toolChoice.required requires tool_use content",
      )
    Some({ mode: Some(Disabled), .. }) if has_tool_use =>
      raise @types.InvalidParams(
        "Sampling toolChoice.none forbids tool_use content",
      )
    _ => ()
  }
}
