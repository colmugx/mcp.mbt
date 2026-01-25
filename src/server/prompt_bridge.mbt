///|
pub fn[T : @prompt.Prompt] PromptRegistry::register_trait_prompt(
  self : PromptRegistry,
  prompt : T,
) -> Unit {
  let name = prompt.name()
  let description = prompt.description()
  let arguments = prompt.arguments()
  let handler = async fn(
    args : Json,
  ) -> Result[@types.GetPromptResult, @types.MCPError] {
    prompt.get(args)
  }
  self.register(name, description, arguments, handler)
}
