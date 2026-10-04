///|
/// An owned compile-once plan. Unsupported schemas fail registration rather
/// than advertising constraints the runtime cannot enforce.
pub struct CompiledSchema {
  priv plan : @schema.Schema
}

///|
pub fn CompiledSchema::compile(
  document : Json,
  label : String,
) -> CompiledSchema raise @types.MCPError {
  let plan = @schema.Schema::compile(document) catch {
    error =>
      raise @types.InvalidParams("Cannot compile " + label + ": \{Repr(error)}")
  }
  { plan, }
}

///|
pub fn CompiledSchema::check_input(
  self : CompiledSchema,
  value : Json,
) -> Unit raise @types.MCPError {
  self.check(value, "inputSchema", false)
}

///|
pub fn CompiledSchema::check_output(
  self : CompiledSchema,
  value : Json,
) -> Unit raise @types.MCPError {
  self.check(value, "outputSchema", true)
}

///|
fn CompiledSchema::check(
  self : CompiledSchema,
  value : Json,
  label : String,
  output : Bool,
) -> Unit raise @types.MCPError {
  let valid = self.plan.valid(value) catch {
    @schema.EvaluationError::DepthLimit(_)
    | @schema.EvaluationError::InvalidNumber(..)
    | @schema.NumericError::InvalidNumber => {
      let message = label +
        ": instance exceeds the supported depth or numeric representation budget"
      if output {
        raise @types.InternalError(message)
      } else {
        raise @types.InvalidParams(message)
      }
    }
    error => raise @types.InternalError(label + " evaluation failed: \{error}")
  }
  if valid {
    return
  }
  let faults = self.plan.faults(value) catch {
    error => raise @types.InternalError(label + " diagnostics failed: \{error}")
  }
  guard faults.get(0) is Some(fault) else {
    raise @types.InternalError(label + ": boolean/diagnostic disagreement")
  }
  let message = label +
    " mismatch at " +
    fault.instance_path +
    " (" +
    fault.keyword +
    "): " +
    fault.message
  if output {
    raise @types.InternalError(message)
  } else {
    raise @types.InvalidParams(message)
  }
}
