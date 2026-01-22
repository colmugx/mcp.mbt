struct ToolEntry {
  name : String
  description : String
  input_schema : Json
  handler : async (Json) -> Result[@mcp.ToolResult, @types.MCPError]
}

pub(all) struct ToolRegistry {
  tools : Array[ToolEntry]
}

pub fn ToolRegistry::new() -> ToolRegistry {
  { tools: [] }
}

pub fn ToolRegistry::register(
  self : ToolRegistry,
  name : String,
  description : String,
  input_schema : Json,
  handler : async (Json) -> Result[@mcp.ToolResult, @types.MCPError],
) -> Unit {
  self.tools.push({ name, description, input_schema, handler })
}

pub fn ToolRegistry::list_tools(self : ToolRegistry) -> Array[@types.ToolDefinition] {
  self.tools.map(fn(entry) {
    {
      name: entry.name,
      description: entry.description,
      input_schema: entry.input_schema,
    }
  })
}

pub async fn ToolRegistry::call_tool(
  self : ToolRegistry,
  name : String,
  params : Json,
) -> Result[@mcp.ToolResult, @types.MCPError] {
  for entry in self.tools {
    if entry.name == name {
      let handler = entry.handler
      return handler(params)
    }
  }
  Err(@types.MethodNotFound("Tool not found: " + name))
}
