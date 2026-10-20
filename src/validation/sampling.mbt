///|
fn sampling_blocks(
  content : @types.SamplingContent,
) -> Array[@types.SamplingContentBlock] {
  match content {
    Single(block) => [block]
    Multiple(blocks) => blocks
  }
}

///|
fn sampling_tool_ids(
  message : @types.SamplingMessage,
) -> (Set[String], Set[String]) raise @types.MCPError {
  let uses : Set[String] = Set([])
  let results : Set[String] = Set([])
  let blocks = sampling_blocks(message.content)
  for block in blocks {
    match block {
      ToolUse(tool) => {
        if message.role != @types.Assistant || uses.contains(tool.id) {
          raise @types.InvalidParams(
            "Sampling tool uses require assistant role and distinct ids",
          )
        }
        uses.add(tool.id)
      }
      ToolResult(tool) => {
        if message.role != @types.User || results.contains(tool.tool_use_id) {
          raise @types.InvalidParams(
            "Sampling tool results require user role and distinct toolUseIds",
          )
        }
        results.add(tool.tool_use_id)
      }
      _ => ()
    }
  }
  if !results.is_empty() && results.length() != blocks.length() {
    raise @types.InvalidParams(
      "Sampling tool-result messages must contain only tool results",
    )
  }
  (uses, results)
}

///|
/// Validate complete tool exchanges before invoking a sampling handler.
pub fn check_sampling_request(
  request : Json,
) -> @types.CreateMessageRequest raise @types.MCPError {
  let request = @types.CreateMessageRequest::from_json(request)
  let mut pending : Set[String] = Set([])
  for message in request.messages {
    let (uses, results) = sampling_tool_ids(message)
    if results.length() != pending.length() ||
      !results.iter().all(id => pending.contains(id)) {
      raise @types.InvalidParams(
        "Sampling tool uses must be immediately followed by exactly matching tool results",
      )
    }
    pending = uses
  }
  if !pending.is_empty() {
    raise @types.InvalidParams("Sampling history has unresolved tool uses")
  }
  request
}

///|
/// Validate the response against the tool-selection policy of its request.
pub fn check_sampling_response(
  request : Json,
  response : Json,
) -> Unit raise @types.MCPError {
  let request = check_sampling_request(request)
  let response = @types.CreateMessageResult::from_json(response)
  let (uses, _) = sampling_tool_ids(
    @types.SamplingMessage::new(response.role, response.content),
  )
  let has_tool_use = !uses.is_empty()
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
