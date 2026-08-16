///| Resource Registry Tests

///| ResourceRegistry basic functionality

///|
test "ResourceRegistry::ResourceRegistry creates empty registry" {
  let registry = ResourceRegistry::ResourceRegistry()
  @debug.assert_eq(registry.list_resources().length(), 0)
}

///|
test "ResourceRegistry::register adds resource entry" {
  let registry = ResourceRegistry::ResourceRegistry()
  registry.register(
    "file:///test.txt",
    "test_resource",
    "Test resource description",
    "text/plain",
    fn() {
      Ok({ uri: "file:///test.txt", content: @resource.Text("test content") })
    },
  )
  @debug.assert_eq(registry.list_resources().length(), 1)
  @debug.assert_eq(registry.list_resources()[0].uri, "file:///test.txt")
  @debug.assert_eq(registry.list_resources()[0].name, "test_resource")
}

///|
test "ResourceRegistry::list_resources returns resource definitions" {
  let registry = ResourceRegistry::ResourceRegistry()
  registry.register(
    "file:///test1.txt",
    "resource1",
    "First resource",
    "text/plain",
    fn() {
      Ok({ uri: "file:///test1.txt", content: @resource.Text("content1") })
    },
  )
  registry.register(
    "file:///test2.txt",
    "resource2",
    "Second resource",
    "text/plain",
    fn() {
      Ok({ uri: "file:///test2.txt", content: @resource.Text("content2") })
    },
  )
  let resources = registry.list_resources()
  @debug.assert_eq(resources.length(), 2)
}

///|
test "ResourceRegistry::list_resources includes optional fields" {
  let registry = ResourceRegistry::ResourceRegistry()
  registry.register(
    "file:///test.txt",
    "test",
    "Test description",
    "text/plain",
    fn() { Ok({ uri: "file:///test.txt", content: @resource.Text("test") }) },
  )
  let resource = registry.list_resources()[0]
  @debug.assert_eq(resource.description, Some("Test description"))
  @debug.assert_eq(resource.mime_type, Some("text/plain"))
}
