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
  prompts : Map[String, PromptEntry]
  mut prompts_list : Array[@prompt.PromptDefinition]
  mut on_change : (() -> Unit)?
}

///|
pub fn PromptRegistry::new() -> PromptRegistry {
  { prompts: Map::default(), prompts_list: [], on_change: None }
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
  let def : @prompt.PromptDefinition = {
    name,
    description: Some(description),
    arguments: Some(arguments),
  }
  self.prompts_list.push(def)
  match self.on_change {
    Some(callback) => callback()
    None => ()
  }
}

///|
pub fn PromptRegistry::list_prompts(
  self : PromptRegistry,
) -> Array[@prompt.PromptDefinition] {
  self.prompts_list
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
