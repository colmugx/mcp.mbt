///| Prompt Registry - Internal prompt management

///|
priv struct PromptEntry {
  name : String
  description : String
  arguments : Array[@types.PromptArgument]
  handler : async (Json) -> Result[@types.GetPromptResult, @types.MCPError]
}

///|
struct PromptRegistry {
  prompts : Map[String, PromptEntry]
}

///|
fn PromptRegistry::PromptRegistry() -> PromptRegistry {
  { prompts: Default::default() }
}

///|

///|
fn PromptRegistry::register(
  self : PromptRegistry,
  name : String,
  description : String,
  arguments : Array[@types.PromptArgument],
  handler : async (Json) -> Result[@types.GetPromptResult, @types.MCPError],
) -> Unit {
  self.prompts.set(name, { name, description, arguments, handler })
}

///|
fn PromptRegistry::list_prompts(
  self : PromptRegistry,
) -> Array[@prompt.PromptDefinition] {
  Array::from_iter(
    self.prompts
    .values()
    .map(fn(entry) {
      {
        name: entry.name,
        description: Some(entry.description),
        arguments: Some(entry.arguments),
      }
    }),
  )
}

///|
async fn PromptRegistry::get_prompt(
  self : PromptRegistry,
  name : String,
  args : Json,
) -> Result[@types.GetPromptResult, @types.MCPError] {
  match self.prompts.get(name) {
    Some(entry) => {
      let handler = entry.handler
      handler(args)
    }
    None => Err(@types.MethodNotFound("Prompt not found: " + name))
  }
}
