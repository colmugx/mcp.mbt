pub fn[T : @mcp.Tool] ToolRegistry::register_trait_tool(
  self : ToolRegistry,
  tool : T,
) -> Unit {
  let name = tool.name()
  let description = tool.description()
  let params = tool.params()

  let input_schema = @mcp.expand_params_to_json(params)

  let handler = async fn(args : Json) -> Result[@mcp.ToolResult, @types.MCPError] {
    Ok(tool.execute(args))
  }

  self.register(name, description, input_schema, handler)
}
