///| Prompt Registry - Internal prompt management

///|
priv struct PromptEntry {
  name : String
  description : String
  arguments : Array[@types.PromptArgument]
  handler : async (Json) -> Result[@prompt.PromptGetOutcome, @types.MCPError]
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
fn PromptRegistry::register(
  self : PromptRegistry,
  name : String,
  description : String,
  arguments : Array[@types.PromptArgument],
  handler : async (Json) -> Result[@prompt.PromptGetOutcome, @types.MCPError],
) -> Unit {
  self.prompts.set(name, { name, description, arguments, handler })
}

///|
fn PromptRegistry::register_simple(
  self : PromptRegistry,
  name : String,
  description : String,
  arguments : Array[@types.PromptArgument],
  handler : async (Json) -> Result[@types.GetPromptResult, @types.MCPError],
) -> Unit {
  let wrapped = async fn(
    params : Json,
  ) -> Result[@prompt.PromptGetOutcome, @types.MCPError] {
    match handler(params) {
      Ok(result) => Ok(@prompt.PromptGetOutcome::Complete(result))
      Err(e) => Err(e)
    }
  }
  self.register(name, description, arguments, wrapped)
}

///|
fn[T : @prompt.Prompt] PromptRegistry::register_trait_prompt(
  self : PromptRegistry,
  prompt : T,
) -> Unit {
  let name = prompt.name()
  let description = prompt.description()
  let arguments = prompt.arguments()
  let handler = async fn(
    params : Json,
  ) -> Result[@prompt.PromptGetOutcome, @types.MCPError] {
    match prompt.get(params) {
      Ok(result) => Ok(@prompt.PromptGetOutcome::Complete(result))
      Err(e) => Err(e)
    }
  }
  self.register(name, description, arguments, handler)
}

///|
fn[T : @prompt.PromptMRTR] PromptRegistry::register_trait_prompt_mrtr(
  self : PromptRegistry,
  prompt : T,
) -> Unit {
  let name = prompt.name()
  let description = prompt.description()
  let arguments = prompt.arguments()
  let handler = async fn(
    params : Json,
  ) -> Result[@prompt.PromptGetOutcome, @types.MCPError] {
    prompt.get(params)
  }
  self.register(name, description, arguments, handler)
}

///|
fn PromptRegistry::list_prompts(
  self : PromptRegistry,
) -> Array[@prompt.PromptDefinition] {
  let entries : Array[PromptEntry] = Array::from_iter(self.prompts.values())
  entries.sort_by(fn(a, b) { a.name.compare(b.name) })
  entries.map(fn(entry) {
    {
      name: entry.name,
      description: Some(entry.description),
      arguments: Some(entry.arguments),
    }
  })
}

///|
async fn PromptRegistry::get_prompt(
  self : PromptRegistry,
  name : String,
  args : Json,
) -> Result[@prompt.PromptGetOutcome, @types.MCPError] {
  match self.prompts.get(name) {
    Some(entry) => {
      let handler = entry.handler
      handler(args)
    }
    None => Err(@types.MethodNotFound("Prompt not found: " + name))
  }
}
