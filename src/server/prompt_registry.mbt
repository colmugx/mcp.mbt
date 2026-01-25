///| Prompt Registry - Internal prompt management

///|
struct PromptEntry {
  name : String
  description : String
  arguments : Array[@types.PromptArgument]
  handler : async (Json) -> Result[@types.GetPromptResult, @types.MCPError]
}

///|
pub(all) struct PromptRegistry {
  prompts : Map[String, PromptEntry] // Name -> Entry mapping for O(1) lookup
  mut on_change : (() -> Unit)? // Callback for list_changed notification
}

///|
pub fn PromptRegistry::new() -> PromptRegistry {
  { prompts: Map::default(), on_change: None }
}

///|
pub fn PromptRegistry::set_on_change(
  self : PromptRegistry,
  callback : () -> Unit,
) -> Unit {
  self.on_change = Some(callback)
}

///|

///|
pub fn PromptRegistry::register(
  self : PromptRegistry,
  name : String,
  description : String,
  arguments : Array[@types.PromptArgument],
  handler : async (Json) -> Result[@types.GetPromptResult, @types.MCPError],
) -> Unit {
  self.prompts.set(name, { name, description, arguments, handler })
  match self.on_change {
    Some(callback) => callback()
    None => ()
  }
}

///|
pub fn PromptRegistry::list_prompts(
  self : PromptRegistry,
) -> Array[@prompt.PromptDefinition] {
  let result : Array[@prompt.PromptDefinition] = []
  self.prompts.each(fn(_name, entry) {
    result.push({
      name: entry.name,
      description: Some(entry.description),
      arguments: Some(entry.arguments),
    })
  })
  result
}

///|
pub async fn PromptRegistry::get_prompt(
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
