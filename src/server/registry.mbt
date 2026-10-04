///|
priv struct ToolEntry {
  definition : @types.ToolDefinition
  input_validator : @validation.CompiledSchema
  output_validator : @validation.CompiledSchema?
  handler : async (@runtime.RequestContext, Json) -> Result[
    @tool.ToolCallOutcome,
    @types.MCPError,
  ]
}

///|
struct ToolRegistry {
  tools : Map[String, ToolEntry]
}

///|
fn ToolRegistry::ToolRegistry() -> ToolRegistry {
  { tools: Default::default(), }
}

///|
fn ToolRegistry::register(
  self : ToolRegistry,
  name : String,
  description : String,
  input_schema : Json,
  handler : async (@runtime.RequestContext, Json) -> Result[
    @tool.ToolCallOutcome,
    @types.MCPError,
  ],
) -> Unit raise @types.MCPError {
  self.register_definition(
    @types.ToolDefinition::new(name, input_schema, description~),
    handler,
  )
}

///|
fn ToolRegistry::register_definition(
  self : ToolRegistry,
  definition : @types.ToolDefinition,
  handler : async (@runtime.RequestContext, Json) -> Result[
    @tool.ToolCallOutcome,
    @types.MCPError,
  ],
) -> Unit raise @types.MCPError {
  let definition = @types.ToolDefinition::from_json(
    @validation.owned_json(definition.to_json()),
  )
  match @transport.validate_tool_header_schema(definition.input_schema) {
    Invalid(reason) =>
      raise @types.InvalidParams("Invalid tool header schema: " + reason)
    Valid(_) => ()
  }
  let input_validator = @validation.CompiledSchema::compile(
    definition.input_schema,
    "inputSchema",
  )
  let output_validator = definition.output_schema.map(schema => {
    @validation.CompiledSchema::compile(schema, "outputSchema")
  })
  self.tools.set(definition.name, {
    definition,
    input_validator,
    output_validator,
    handler,
  })
}

///|
fn ToolRegistry::list_tools(
  self : ToolRegistry,
) -> Array[@types.ToolDefinition] {
  let entries : Array[ToolEntry] = Array::from_iter(self.tools.values())
  entries.sort_by(fn(a, b) { a.definition.name.compare(b.definition.name) })
  entries.map(fn(entry) { entry.definition })
}

///|
async fn ToolRegistry::call_tool(
  self : ToolRegistry,
  name : String,
  context : @runtime.RequestContext,
  params : Json,
) -> Result[@tool.ToolCallOutcome, @types.MCPError] {
  match self.tools.get(name) {
    Some(entry) => {
      entry.input_validator.check_input(params) catch {
        error => return Err(error)
      }
      context.cancellation_token.throw_if_cancelled()
      let outcome = (entry.handler)(context, params)
      context.cancellation_token.throw_if_cancelled()
      match outcome {
        Ok(@tool.Complete(result)) => {
          if result.is_error != Some(true) &&
            entry.output_validator is Some(validator) {
            let value = match result.structured_content {
              Some(value) => value
              None =>
                return Err(
                  @types.InternalError(
                    "Tool declared outputSchema but successful result has no structuredContent",
                  ),
                )
            }
            validator.check_output(value) catch {
              error => return Err(error)
            }
          }
          outcome
        }
        _ => outcome
      }
    }
    None => Err(@types.InvalidParams("Tool not found: " + name))
  }
}
