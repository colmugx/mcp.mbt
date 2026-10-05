///|
pub fn check_roots_request(value : Json) -> Unit raise @types.MCPError {
  guard value is Object(fields) else {
    raise @types.InvalidParams("roots/list params must be an object")
  }
  match fields.get("_meta") {
    None | Some(Object(_)) => ()
    Some(_) => raise @types.InvalidParams("roots/list _meta must be an object")
  }
}

///|
pub fn check_roots_response(value : Json) -> Unit raise @types.MCPError {
  guard value is { "roots": Array(roots), .. } else {
    raise @types.InvalidParams("roots/list response requires a roots array")
  }
  for root in roots {
    guard root is Object(fields) else {
      raise @types.InvalidParams("Root must be an object")
    }
    guard fields.get("uri") is Some(String(uri)) && uri.has_prefix("file://") else {
      raise @types.InvalidParams("Root URI must start with file://")
    }
    match fields.get("name") {
      None | Some(String(_)) => ()
      Some(_) => raise @types.InvalidParams("Root name must be a string")
    }
    match fields.get("_meta") {
      None | Some(Object(_)) => ()
      Some(_) => raise @types.InvalidParams("Root _meta must be an object")
    }
  }
}

///|
pub fn check_input_response(
  method_name : String,
  request : Json,
  response : Json,
) -> Unit raise @types.MCPError {
  match method_name {
    "elicitation/create" =>
      ElicitationValidator::compile(request).check_response(response)
    "sampling/createMessage" =>
      ignore(@types.CreateMessageResult::from_json(response))
    "roots/list" => check_roots_response(response)
    _ =>
      raise @types.InvalidParams("Unknown input request method: " + method_name)
  }
}

///|
/// Without continuation state there is no trusted request to correlate against,
/// but the value must still be a member of the official InputResponse union.
pub fn check_unbound_input_response(
  response : Json,
) -> Unit raise @types.MCPError {
  let elicitation = Some(@types.ElicitationResult::from_json(response)) catch {
    @types.InvalidParams(_) => None
    error => raise error
  }
  if elicitation is Some(result) &&
    (result.action == @types.Accept || result.content is None) {
    return
  }
  let roots_valid = try {
    check_roots_response(response)
    true
  } catch {
    @types.InvalidParams(_) => false
    error => raise error
  }
  if roots_valid {
    return
  }
  let sampling_valid = try {
    ignore(@types.CreateMessageResult::from_json(response))
    true
  } catch {
    @types.InvalidParams(_) => false
    error => raise error
  }
  if !sampling_valid {
    raise @types.InvalidParams(
      "Value is not a supported InputResponse union member",
    )
  }
}
