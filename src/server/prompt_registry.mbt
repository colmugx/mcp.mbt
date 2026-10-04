///| Prompt Registry - Internal prompt management

///|
priv struct PromptEntry {
  definition : @types.PromptDefinition
  handler : async (@runtime.RequestContext, Json) -> Result[
    @prompt.PromptGetOutcome,
    @types.MCPError,
  ]
}

///|
struct PromptRegistry {
  prompts : Map[String, PromptEntry]
}

///|
fn PromptRegistry::PromptRegistry() -> PromptRegistry {
  { prompts: Default::default(), }
}

///|
fn PromptRegistry::register(
  self : PromptRegistry,
  name : String,
  description : String,
  arguments : Array[@types.PromptArgument],
  handler : async (@runtime.RequestContext, Json) -> Result[
    @prompt.PromptGetOutcome,
    @types.MCPError,
  ],
) -> Unit {
  self.register_definition(
    @types.PromptDefinition::new(name, description~, arguments~),
    handler,
  )
}

///|
fn PromptRegistry::register_definition(
  self : PromptRegistry,
  definition : @types.PromptDefinition,
  handler : async (@runtime.RequestContext, Json) -> Result[
    @prompt.PromptGetOutcome,
    @types.MCPError,
  ],
) -> Unit {
  self.prompts.set(definition.name, { definition, handler, })
}

///|
fn PromptRegistry::register_simple(
  self : PromptRegistry,
  name : String,
  description : String,
  arguments : Array[@types.PromptArgument],
  handler : async (@runtime.RequestContext, Json) -> Result[
    @types.GetPromptResult,
    @types.MCPError,
  ],
) -> Unit {
  let wrapped = async fn(
    context : @runtime.RequestContext,
    params : Json,
  ) -> Result[@prompt.PromptGetOutcome, @types.MCPError] {
    match handler(context, params) {
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
    context : @runtime.RequestContext,
    params : Json,
  ) -> Result[@prompt.PromptGetOutcome, @types.MCPError] {
    match prompt.get(context, params) {
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
    context : @runtime.RequestContext,
    params : Json,
  ) -> Result[@prompt.PromptGetOutcome, @types.MCPError] {
    prompt.get(context, params)
  }
  self.register(name, description, arguments, handler)
}

///|
fn PromptRegistry::list_prompts(
  self : PromptRegistry,
) -> Array[@prompt.PromptDefinition] {
  let entries : Array[PromptEntry] = Array::from_iter(self.prompts.values())
  entries.sort_by(fn(a, b) { a.definition.name.compare(b.definition.name) })
  entries.map(fn(entry) { entry.definition })
}

///|
async fn PromptRegistry::get_prompt(
  self : PromptRegistry,
  name : String,
  context : @runtime.RequestContext,
  args : Json,
) -> Result[@prompt.PromptGetOutcome, @types.MCPError] {
  match self.prompts.get(name) {
    Some(entry) => {
      let handler = entry.handler
      handler(context, args)
    }
    None => Err(@types.MethodNotFound("Prompt not found: " + name))
  }
}
