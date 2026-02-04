///| Resource Registry - Internal resource management

///|
pub struct ResourceEntry {
  name : String
  description : String
  uri : String
  mime_type : String
  handler : async () -> Result[@resource.ResourceReadResult, @types.MCPError]
}

///|
pub(all) struct ResourceRegistry {
  resources : Map[String, ResourceEntry]
  mut resources_list : Array[@resource.ResourceDefinition]
  mut subscriptions : Array[String]
  mut on_change : (() -> Unit)?
}

///|
pub fn ResourceRegistry::new() -> ResourceRegistry {
  {
    resources: Map::default(),
    resources_list: [],
    subscriptions: [],
    on_change: None,
  }
}

///|
pub fn ResourceRegistry::set_on_change(
  self : ResourceRegistry,
  callback : () -> Unit,
) -> Unit {
  self.on_change = Some(callback)
}

///|

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
  let def : @resource.ResourceDefinition = {
    uri,
    name,
    description: Some(description),
    mime_type: Some(mime_type),
  }
  self.resources_list.push(def)
  match self.on_change {
    Some(callback) => callback()
    None => ()
  }
}

///|
pub fn ResourceRegistry::list_resources(
  self : ResourceRegistry,
) -> Array[@resource.ResourceDefinition] {
  self.resources_list
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
