///| Resource Registry - Internal resource management

///|
priv struct ResourceEntry {
  definition : @types.ResourceDefinition
  handler : async (@runtime.RequestContext, Json) -> Result[
    @resource.ResourceReadOutcome,
    @types.MCPError,
  ]
}

///|
struct ResourceRegistry {
  resources : Map[String, ResourceEntry]
  templates : Map[String, @types.ResourceTemplateDefinition]
}

///|
fn ResourceRegistry::ResourceRegistry() -> ResourceRegistry {
  { resources: Default::default(), templates: Default::default(), }
}

///|
fn ResourceRegistry::register(
  self : ResourceRegistry,
  uri : String,
  name : String,
  description : String,
  mime_type : String,
  handler : async (@runtime.RequestContext, Json) -> Result[
    @resource.ResourceReadOutcome,
    @types.MCPError,
  ],
) -> Unit {
  self.register_definition(
    @types.ResourceDefinition::new(uri, name, description~, mime_type~),
    handler,
  )
}

///|
fn ResourceRegistry::register_definition(
  self : ResourceRegistry,
  definition : @types.ResourceDefinition,
  handler : async (@runtime.RequestContext, Json) -> Result[
    @resource.ResourceReadOutcome,
    @types.MCPError,
  ],
) -> Unit {
  self.resources.set(definition.uri, { definition, handler, })
}

///|
fn ResourceRegistry::register_simple(
  self : ResourceRegistry,
  uri : String,
  name : String,
  description : String,
  mime_type : String,
  handler : async (@runtime.RequestContext) -> Result[
    @resource.ResourceReadResult,
    @types.MCPError,
  ],
) -> Unit {
  let wrapped = async fn(
    context : @runtime.RequestContext,
    _params : Json,
  ) -> Result[@resource.ResourceReadOutcome, @types.MCPError] {
    match handler(context) {
      Ok(result) => Ok(@resource.ResourceReadOutcome::Complete(result))
      Err(e) => Err(e)
    }
  }
  self.register(uri, name, description, mime_type, wrapped)
}

///|
fn[T : @resource.Resource] ResourceRegistry::register_trait_resource(
  self : ResourceRegistry,
  resource : T,
) -> Unit {
  let name = resource.name()
  let description = resource.description()
  let uri = resource.uri()
  let mime_type = resource.mime_type()
  let handler = async fn(
    context : @runtime.RequestContext,
    _params : Json,
  ) -> Result[@resource.ResourceReadOutcome, @types.MCPError] {
    match resource.read(context) {
      Ok(result) => Ok(@resource.ResourceReadOutcome::Complete(result))
      Err(e) => Err(e)
    }
  }
  self.register(uri, name, description, mime_type, handler)
}

///|
fn[T : @resource.ResourceMRTR] ResourceRegistry::register_trait_resource_mrtr(
  self : ResourceRegistry,
  resource : T,
) -> Unit {
  let name = resource.name()
  let description = resource.description()
  let uri = resource.uri()
  let mime_type = resource.mime_type()
  let handler = async fn(
    context : @runtime.RequestContext,
    params : Json,
  ) -> Result[@resource.ResourceReadOutcome, @types.MCPError] {
    resource.read(context, params)
  }
  self.register(uri, name, description, mime_type, handler)
}

///|
fn ResourceRegistry::register_template(
  self : ResourceRegistry,
  uri_template : String,
  name : String,
  description : String?,
  mime_type : String?,
) -> Unit {
  self.register_template_definition(
    @types.ResourceTemplateDefinition::new(
      uri_template,
      name,
      description?,
      mime_type?,
    ),
  )
}

///|
fn ResourceRegistry::register_template_definition(
  self : ResourceRegistry,
  definition : @types.ResourceTemplateDefinition,
) -> Unit {
  self.templates.set(definition.uri_template, definition)
}

///|
fn ResourceRegistry::list_resources(
  self : ResourceRegistry,
) -> Array[@resource.ResourceDefinition] {
  let entries : Array[ResourceEntry] = Array::from_iter(self.resources.values())
  entries.sort_by(fn(a, b) { a.definition.uri.compare(b.definition.uri) })
  entries.map(fn(entry) { entry.definition })
}

///|
fn ResourceRegistry::list_templates(
  self : ResourceRegistry,
) -> Array[@resource.ResourceTemplateDefinition] {
  let entries = Array::from_iter(self.templates.values())
  entries.sort_by(fn(a, b) { a.uri_template.compare(b.uri_template) })
  entries
}

///|
async fn ResourceRegistry::read_resource(
  self : ResourceRegistry,
  uri : String,
  context : @runtime.RequestContext,
  params : Json,
) -> Result[@resource.ResourceReadOutcome, @types.MCPError] {
  match self.resources.get(uri) {
    Some(entry) => {
      let handler = entry.handler
      handler(context, params)
    }
    // Per 2026-07-28 spec, resource-not-found is InvalidParams (-32602),
    // not the old -32002 or MethodNotFound.
    None => Err(@types.InvalidParams("Resource not found: " + uri))
  }
}
