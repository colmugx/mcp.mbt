///|
pub fn[T : @tool.Tool] ToolRegistry::register_trait_tool(
  self : ToolRegistry,
  tool : T,
) -> Unit {
  let name = tool.name()
  let description = tool.description()
  let params = tool.params()
  let input_schema = expand_params_to_json(params)
  let handler = async fn(
    args : Json,
  ) -> Result[@tool.ToolResult, @types.MCPError] {
    Ok(tool.execute(args))
  }
  self.register(name, description, input_schema, handler)
}
