///|
/// Modern MRTR and legacy duplex requests share the same fail-closed form
/// validation. Compile before calling user code so it cannot weaken the schema.
fn invoke_elicitation(
  handler : (Json) -> Result[@types.ElicitationResult, @types.MCPError],
  params : Json,
) -> Json raise @types.MCPError {
  let validator = @validation.ElicitationValidator::compile(params)
  let result = match handler(params) {
    Ok(result) => result
    Err(error) => raise error
  }
  let response = result.to_json()
  validator.check_response(response)
  response
}
