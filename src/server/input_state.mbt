///|
/// Keep response correlation inside the authenticated blob, not server memory
/// or client-supplied retry parameters. Business state remains opaque to this
/// envelope and is unwrapped unchanged into RequestContext.
fn sealed_input_state(
  state : Json,
  requests : Map[String, @types.InputRequestEntry],
) -> Json {
  let inputs : Map[String, Json] = Map([])
  for key, entry in requests {
    inputs[key] = {
      "method": entry.method_name.to_method(),
      "params": entry.params,
    }
  }
  {
    "mrtrVersion": 1,
    "continuation": state,
    "inputRequests": Json::object(inputs),
  }
}

///|
fn restore_input_state(
  state : Json,
  responses : Map[String, Json],
) -> Json raise @types.MCPError {
  guard state
    is {
      "mrtrVersion": Number(1, ..),
      "continuation": continuation,
      "inputRequests": Object(requests),
      ..
    } else {
    raise @types.InvalidParams("Unsupported MRTR continuation envelope")
  }
  if requests.length() != responses.length() {
    raise @types.InvalidParams(
      "inputResponses must match the requested input keys",
    )
  }
  for key, request in requests {
    guard responses.get(key) is Some(response) else {
      raise @types.InvalidParams("Missing input response: " + key)
    }
    guard request is { "method": String(method_name), "params": params, .. } else {
      raise @types.InternalError("Malformed authenticated input request")
    }
    @validation.check_input_response(method_name, params, response)
  }
  continuation
}
