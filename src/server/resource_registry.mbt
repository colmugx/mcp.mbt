///| Resource Registry - Internal resource management

///|
struct ResourceEntry {
  name : String
  description : String
  uri : String
  mime_type : String
  handler : async () -> Result[@resource.ResourceReadResult, @types.MCPError]
}

///|
pub(all) struct ResourceRegistry {
  resources : Map[String, ResourceEntry]  // URI -> Entry mapping for O(1) lookup
  mut subscriptions : Array[String]  // Subscribed URIs
}

///|
pub fn ResourceRegistry::new() -> ResourceRegistry {
  { resources: Map::default(), subscriptions: [] }
}

///|
pub fn ResourceRegistry::register(
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
pub fn ResourceRegistry::list_resources(
  self : ResourceRegistry,
) -> Array[@resource.ResourceDefinition] {
  let result : Array[@resource.ResourceDefinition] = []
  self.resources.each(fn(_uri, entry) {
    result.push({
      uri: entry.uri,
      name: entry.name,
      description: Some(entry.description),
      mime_type: Some(entry.mime_type),
    })
  })
  result
}

///|
pub async fn ResourceRegistry::read_resource(
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
pub fn ResourceRegistry::subscribe(
  self : ResourceRegistry,
  uri : String,
) -> Result[Unit, @types.MCPError] {
  match self.resources.get(uri) {
    Some(_) => {
      let found = self.subscriptions.iter().any(fn(u) { u == uri })
      if not(found) {
        self.subscriptions.push(uri)
      }
      Ok(())
    }
    None => Err(@types.MethodNotFound("Resource not found: " + uri))
  }
}

///|
pub fn ResourceRegistry::unsubscribe(
  self : ResourceRegistry,
  uri : String,
) -> Result[Unit, @types.MCPError] {
  self.subscriptions = self.subscriptions.filter(fn(u) { u != uri })
  Ok(())
}
