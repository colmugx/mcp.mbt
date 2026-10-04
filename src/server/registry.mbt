///|
priv struct ToolEntry {
  definition : @types.ToolDefinition
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
  ignore(@types.ToolDefinition::from_json(definition.to_json()))
  match @transport.validate_tool_header_schema(definition.input_schema) {
    Invalid(reason) =>
      raise @types.InvalidParams("Invalid tool header schema: " + reason)
    Valid(_) => ()
  }
  self.tools.set(definition.name, { definition, handler, })
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
      let handler = entry.handler
      handler(context, params)
    }
    None => Err(@types.InvalidParams("Tool not found: " + name))
  }
}
