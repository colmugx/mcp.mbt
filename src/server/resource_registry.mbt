///| Resource Registry - Internal resource management

///|
priv struct ResourceEntry {
  name : String
  description : String
  uri : String
  mime_type : String
  handler : async (Json) -> Result[
    @resource.ResourceReadOutcome,
    @types.MCPError,
  ]
}

///|
priv struct ResourceTemplateEntry {
  uri_template : String
  name : String
  description : String?
  mime_type : String?
}

///|
struct ResourceRegistry {
  resources : Map[String, ResourceEntry]
  templates : Map[String, ResourceTemplateEntry]
}

///|
fn ResourceRegistry::ResourceRegistry() -> ResourceRegistry {
  { resources: Default::default(), templates: Default::default() }
}

///|
fn ResourceRegistry::register(
  self : ResourceRegistry,
  uri : String,
  name : String,
  description : String,
  mime_type : String,
  handler : async (Json) -> Result[
    @resource.ResourceReadOutcome,
    @types.MCPError,
  ],
) -> Unit {
  self.resources.set(uri, { name, description, uri, mime_type, handler })
}

///|
fn ResourceRegistry::register_simple(
  self : ResourceRegistry,
  uri : String,
  name : String,
  description : String,
  mime_type : String,
  handler : async () -> Result[@resource.ResourceReadResult, @types.MCPError],
) -> Unit {
  let wrapped = async fn(
    _params : Json,
  ) -> Result[@resource.ResourceReadOutcome, @types.MCPError] {
    match handler() {
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
    _params : Json,
  ) -> Result[@resource.ResourceReadOutcome, @types.MCPError] {
    match resource.read() {
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
    params : Json,
  ) -> Result[@resource.ResourceReadOutcome, @types.MCPError] {
    resource.read(params)
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
  self.templates.set(uri_template, {
    uri_template,
    name,
    description,
    mime_type,
  })
}

///|
fn ResourceRegistry::list_resources(
  self : ResourceRegistry,
) -> Array[@resource.ResourceDefinition] {
  let entries : Array[ResourceEntry] = Array::from_iter(self.resources.values())
  entries.sort_by(fn(a, b) { a.uri.compare(b.uri) })
  entries.map(fn(entry) {
    {
      uri: entry.uri,
      name: entry.name,
      description: Some(entry.description),
      mime_type: Some(entry.mime_type),
    }
  })
}

///|
fn ResourceRegistry::list_templates(
  self : ResourceRegistry,
) -> Array[@resource.ResourceTemplateDefinition] {
  let entries : Array[ResourceTemplateEntry] = Array::from_iter(
    self.templates.values(),
  )
  entries.sort_by(fn(a, b) { a.uri_template.compare(b.uri_template) })
  entries.map(fn(entry) {
    {
      uri_template: entry.uri_template,
      name: entry.name,
      description: entry.description,
      mime_type: entry.mime_type,
    }
  })
}

///|
async fn ResourceRegistry::read_resource(
  self : ResourceRegistry,
  uri : String,
  params : Json,
) -> Result[@resource.ResourceReadOutcome, @types.MCPError] {
  match self.resources.get(uri) {
    Some(entry) => {
      let handler = entry.handler
      handler(params)
    }
    // Per 2026-07-28 spec, resource-not-found is InvalidParams (-32602),
    // not the old -32002 or MethodNotFound.
    None => Err(@types.InvalidParams("Resource not found: " + uri))
  }
}
