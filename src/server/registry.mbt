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
  // Rebuilt only when a tool is registered or replaced.
  mut sorted_definitions : Array[@types.ToolDefinition]
  // Serialized definitions are immutable while the registry is unchanged.
  // Only the private tools/list encoder consumes these JSON values.
  mut sorted_definition_jsons : Array[Json]
  mut sorted_definitions_valid : Bool
}

///|
fn ToolRegistry::ToolRegistry() -> ToolRegistry {
  {
    tools: Default::default(),
    sorted_definitions: [],
    sorted_definition_jsons: [],
    sorted_definitions_valid: true,
  }
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
  schema_resources? : Map[String, Json],
  input_base_uri? : String,
  output_base_uri? : String,
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
    resources?=schema_resources,
    base_uri?=input_base_uri,
  )
  let output_validator = definition.output_schema.map(schema => {
    @validation.CompiledSchema::compile(
      schema,
      "outputSchema",
      resources?=schema_resources,
      base_uri?=output_base_uri,
    )
  })
  self.tools.set(definition.name, {
    definition,
    input_validator,
    output_validator,
    handler,
  })
  self.sorted_definitions_valid = false
}

///|
fn ToolRegistry::refresh_sorted_definitions(self : ToolRegistry) -> Unit {
  if !self.sorted_definitions_valid {
    let entries : Array[ToolEntry] = Array::from_iter(self.tools.values())
    entries.sort_by(fn(a, b) { a.definition.name.compare(b.definition.name) })
    self.sorted_definitions = entries.map(fn(entry) { entry.definition })
    // Tool registration already takes an owned snapshot. Rebuild wire JSON
    // alongside the sorted list, then reuse it until the next registration.
    self.sorted_definition_jsons = self.sorted_definitions.map(
      @types.ToolDefinition::to_json,
    )
    self.sorted_definitions_valid = true
  }
}

///|
fn ToolRegistry::list_tools(
  self : ToolRegistry,
) -> Array[@types.ToolDefinition] {
  self.refresh_sorted_definitions()
  // Preserve the previous API contract: callers receive their own array.
  self.sorted_definitions.map(fn(definition) { definition })
}

///|
/// Internal-only, read-only wire view. Do not mutate returned Json objects:
/// they are the registry's owned cached values.
fn ToolRegistry::list_tool_jsons(self : ToolRegistry) -> Array[Json] {
  self.refresh_sorted_definitions()
  self.sorted_definition_jsons.map(fn(definition) { definition })
}

///|
async fn ToolRegistry::call_tool(
  self : ToolRegistry,
  name : String,
  context : @runtime.RequestContext,
  params : Json,
) -> @tool.ToolCallOutcome {
  match self.tools.get(name) {
    Some(entry) => {
      entry.input_validator.check_input(params)
      context.cancellation_token.throw_if_cancelled()
      let outcome = (entry.handler)(context, params)
      context.cancellation_token.throw_if_cancelled()
      let outcome = match outcome {
        Ok(outcome) => outcome
        Err(error) => raise error
      }
      match outcome {
        @tool.Complete(result) => {
          if result.is_error != Some(true) &&
            entry.output_validator is Some(validator) {
            let value = match result.structured_content {
              Some(value) => value
              None =>
                raise @types.InternalError(
                  "Tool declared outputSchema but successful result has no structuredContent",
                )
            }
            validator.check_output(value)
          }
          outcome
        }
        _ => outcome
      }
    }
    None => raise @types.InvalidParams("Tool not found: " + name)
  }
}
