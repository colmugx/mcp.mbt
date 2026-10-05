///|
/// A snapshot of the requested form's constraints, compiled before user code
/// runs. URL mode deliberately has no form validator.
pub struct ElicitationValidator {
  priv form : CompiledSchema?
}

///|
pub fn ElicitationValidator::compile(
  request : Json,
) -> ElicitationValidator raise @types.MCPError {
  let request = @types.ElicitationRequest::from_json(owned_json(request))
  let form = match request {
    Form(_, requested_schema~, ..) =>
      Some(
        CompiledSchema::compile(requested_schema, "elicitation requestedSchema"),
      )
    Url(_, ..) => None
  }
  { form, }
}

///|
/// Validate raw content so decimal constraints are not rounded through the
/// convenience ElicitationValue::Number(Double) model.
pub fn ElicitationValidator::check_response(
  self : ElicitationValidator,
  response : Json,
) -> Unit raise @types.MCPError {
  let result = @types.ElicitationResult::from_json(response)
  match (self.form, result.action) {
    (Some(plan), @types.Accept) => {
      guard response is Object(fields) && fields.get("content") is Some(content) else {
        raise @types.InvalidParams("Accepted form elicitation requires content")
      }
      plan.check_input(content)
    }
    _ =>
      if result.content is Some(_) {
        raise @types.InvalidParams(
          "Elicitation content is only allowed for accepted forms",
        )
      }
  }
}
