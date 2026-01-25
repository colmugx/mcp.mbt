///|
struct ToolEntry {
  name : String
  description : String
  input_schema : Json
  handler : async (Json) -> Result[@tool.ToolResult, @types.MCPError]
}

///|
pub(all) struct ToolRegistry {
  tools : Map[String, ToolEntry]
  mut tools_list : Array[@types.ToolDefinition]
  mut on_change : (() -> Unit)?
}

///|
pub fn ToolRegistry::new() -> ToolRegistry {
  { tools: Map::default(), tools_list: [], on_change: None }
}

///|
pub fn ToolRegistry::register(
  self : ToolRegistry,
  name : String,
  description : String,
  input_schema : Json,
  handler : async (Json) -> Result[@tool.ToolResult, @types.MCPError],
) -> Unit {
  self.tools.set(name, { name, description, input_schema, handler })
  let definitions : Array[@types.ToolDefinition] = []
  self.tools.each(fn(_name, entry) {
    let def : @types.ToolDefinition = {
      name: entry.name,
      description: entry.description,
      input_schema: entry.input_schema,
    }
    definitions.push(def)
  })
  self.tools_list = definitions
  match self.on_change {
    Some(callback) => callback()
    None => ()
  }
}

///|
pub fn ToolRegistry::list_tools(
  self : ToolRegistry,
) -> Array[@types.ToolDefinition] {
  self.tools_list
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
