///|
pub struct ToolEntry {
  name : String
  description : String
  input_schema : Json
  cached_schema_json : String
  handler : async (Json) -> Result[@tool.ToolResult, @types.MCPError]
}

///|
pub(all) struct ToolRegistry {
  tools : Map[String, ToolEntry]
  mut on_change : (() -> Unit)?
}

///|
pub fn ToolRegistry::new() -> ToolRegistry {
  { tools: Map::default(), on_change: None }
}

///|
pub fn ToolRegistry::register(
  self : ToolRegistry,
  name : String,
  description : String,
  input_schema : Json,
  handler : async (Json) -> Result[@tool.ToolResult, @types.MCPError],
) -> Unit {
  let cached_schema_json = input_schema.stringify()
  self.tools.set(name, {
    name,
    description,
    input_schema,
    cached_schema_json,
    handler,
  })
  match self.on_change {
    Some(callback) => callback()
    None => ()
  }
}

///|
pub fn ToolRegistry::list_tools(
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
pub fn ToolRegistry::set_on_change(
  self : ToolRegistry,
  callback : () -> Unit,
) -> Unit {
  self.on_change = Some(callback)
}

///|
pub async fn ToolRegistry::call_tool(
  self : ToolRegistry,
  name : String,
  params : Json,
) -> Result[@tool.ToolResult, @types.MCPError] {
  match self.tools.get(name) {
    Some(entry) => {
      let handler = entry.handler
      handler(params)
    }
    None => Err(@types.MethodNotFound("Tool not found: " + name))
  }
}
