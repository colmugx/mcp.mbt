///| Resource Registry - Internal resource management

///|
priv struct ResourceEntry {
  name : String
  description : String
  uri : String
  mime_type : String
  handler : async () -> Result[@resource.ResourceReadResult, @types.MCPError]
}

///|
struct ResourceRegistry {
  resources : Map[String, ResourceEntry]
  mut subscriptions : Array[String]
}

///|
fn ResourceRegistry::ResourceRegistry() -> ResourceRegistry {
  { resources: Default::default(), subscriptions: [] }
}

///|

///|
fn ResourceRegistry::register(
  self : ResourceRegistry,
  uri : String,
  name : String,
  description : String,
  mime_type : String,
  handler : async () -> Result[@resource.ResourceReadResult, @types.MCPError],
) -> Unit {
  self.resources.set(uri, { name, description, uri, mime_type, handler })
}

///|
fn ResourceRegistry::list_resources(
  self : ResourceRegistry,
) -> Array[@resource.ResourceDefinition] {
  Array::from_iter(
    self.resources
    .values()
    .map(fn(entry) {
      {
        uri: entry.uri,
        name: entry.name,
        description: Some(entry.description),
        mime_type: Some(entry.mime_type),
      }
    }),
  )
}

///|
async fn ResourceRegistry::read_resource(
  self : ResourceRegistry,
  uri : String,
) -> Result[@resource.ResourceReadResult, @types.MCPError] {
  match self.resources.get(uri) {
    Some(entry) => {
      let handler = entry.handler
      handler()
    }
    None => Err(@types.MethodNotFound("Resource not found: " + uri))
  }
}

///|
fn ResourceRegistry::subscribe(
  self : ResourceRegistry,
  uri : String,
) -> Result[Unit, @types.MCPError] {
  match self.resources.get(uri) {
    Some(_) => {
      let found = self.subscriptions.iter().any(fn(u) { u == uri })
      if !found {
        self.subscriptions.push(uri)
      }
      Ok(())
    }
    None => Err(@types.MethodNotFound("Resource not found: " + uri))
  }
}

///|
fn ResourceRegistry::unsubscribe(
  self : ResourceRegistry,
  uri : String,
) -> Result[Unit, @types.MCPError] {
  self.subscriptions = self.subscriptions.filter(fn(u) { u != uri })
  Ok(())
}
