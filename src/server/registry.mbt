///|
priv struct ToolEntry {
  name : String
  description : String
  input_schema : Json
  cached_schema_json : String
  handler : async (Json) -> Result[@tool.ToolCallOutcome, @types.MCPError]
}

///|
struct ToolRegistry {
  tools : Map[String, ToolEntry]
}

///|
fn ToolRegistry::ToolRegistry() -> ToolRegistry {
  { tools: Default::default() }
}

///|
fn ToolRegistry::register(
  self : ToolRegistry,
  name : String,
  description : String,
  input_schema : Json,
  handler : async (Json) -> Result[@tool.ToolCallOutcome, @types.MCPError],
) -> Unit {
  let cached_schema_json = input_schema.stringify()
  self.tools.set(name, {
    name,
    description,
    input_schema,
    cached_schema_json,
    handler,
  })
}

///|
fn ToolRegistry::list_tools(
  self : ToolRegistry,
) -> Array[@types.ToolDefinition] {
  Array::from_iter(
    self.tools
    .values()
    .map(fn(entry) {
      {
        name: entry.name,
        description: entry.description,
        input_schema: entry.input_schema,
        cached_schema_json: entry.cached_schema_json,
        icon: None,
      }
    }),
  )
}

///|
async fn ToolRegistry::call_tool(
  self : ToolRegistry,
  name : String,
  params : Json,
) -> Result[@tool.ToolCallOutcome, @types.MCPError] {
  match self.tools.get(name) {
    Some(entry) => {
      let handler = entry.handler
      handler(params)
    }
    None => Err(@types.MethodNotFound("Tool not found: " + name))
  }
}
