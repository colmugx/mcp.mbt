///|
test "sampling tool choice correlates single and multiple response blocks" {
  let text : Json = { "type": "text", "text": "done" }
  let tool : Json = {
    "type": "tool_use",
    "id": "u1",
    "name": "inspect",
    "input": {},
  }
  for mode in ["required", "none", "auto"] {
    let request : Json = {
      "messages": [],
      "maxTokens": 1,
      "toolChoice": { "mode": mode },
    }
    for
      (content, has_tool) in [
        (text, false),
        (tool, true),
        (Json::array([text]), false),
        (Json::array([text, tool]), true),
      ] {
      let response : Json = {
        "role": "assistant",
        "model": "model",
        "content": content,
      }
      let rejected = (mode == "required" && !has_tool) ||
        (mode == "none" && has_tool)
      if rejected {
        try @validation.check_sampling_response(request, response) catch {
          @types.InvalidParams(_) => ()
          error => raise error
        } noraise {
          _ => fail("sampling tool selection policy must be enforced")
        }
      } else {
        @validation.check_sampling_response(request, response)
        @validation.check_input_response(
          "sampling/createMessage", request, response,
        )
      }
    }
  }
  @validation.check_sampling_response({ "messages": [], "maxTokens": 1 }, {
    "role": "assistant",
    "model": "model",
    "content": text,
  })
}
