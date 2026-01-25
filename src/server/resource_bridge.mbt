///|
pub fn[T : @resource.Resource] ResourceRegistry::register_trait_resource(
  self : ResourceRegistry,
  resource : T,
) -> Unit {
  let uri = resource.uri()
  let name = resource.name()
  let description = resource.description()
  let mime_type = resource.mime_type()
  let handler = async fn() -> Result[
    @resource.ResourceReadResult,
    @types.MCPError,
  ] {
    resource.read()
  }
  self.register(uri, name, description, mime_type, handler)
}
