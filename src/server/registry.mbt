///|
priv struct ToolEntry {
  name : String
  description : String
  input_schema : Json
  handler : async (Json) -> Result[@tool.ToolCallOutcome, @types.MCPError]
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
  handler : async (Json) -> Result[@tool.ToolCallOutcome, @types.MCPError],
) -> Unit {
  self.tools.set(name, { name, description, input_schema, handler, })
}

///|
fn ToolRegistry::list_tools(
  self : ToolRegistry,
) -> Array[@types.ToolDefinition] {
  let entries : Array[ToolEntry] = Array::from_iter(self.tools.values())
  entries.sort_by(fn(a, b) { a.name.compare(b.name) })
  entries.map(fn(entry) {
    {
      name: entry.name,
      description: entry.description,
      input_schema: entry.input_schema,
    }
  })
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
