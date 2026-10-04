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
  registry.register_simple(
    "file:///test.txt",
    "test_resource",
    "Test resource description",
    "text/plain",
    fn(_context) {
      Ok(
        @resource.ResourceReadResult::text(
          "test content",
          uri="file:///test.txt",
        ),
      )
    },
  )
  @debug.assert_eq(registry.list_resources().length(), 1)
  @debug.assert_eq(registry.list_resources()[0].uri, "file:///test.txt")
  @debug.assert_eq(registry.list_resources()[0].name, "test_resource")
}

///|
test "ResourceRegistry::list_resources returns resource definitions" {
  let registry = ResourceRegistry::ResourceRegistry()
  registry.register_simple(
    "file:///test1.txt",
    "resource1",
    "First resource",
    "text/plain",
    fn(_context) {
      Ok(
        @resource.ResourceReadResult::text("content1", uri="file:///test1.txt"),
      )
    },
  )
  registry.register_simple(
    "file:///test2.txt",
    "resource2",
    "Second resource",
    "text/plain",
    fn(_context) {
      Ok(
        @resource.ResourceReadResult::text("content2", uri="file:///test2.txt"),
      )
    },
  )
  let resources = registry.list_resources()
  @debug.assert_eq(resources.length(), 2)
}

///|
test "ResourceRegistry::list_resources includes optional fields" {
  let registry = ResourceRegistry::ResourceRegistry()
  registry.register_simple(
    "file:///test.txt",
    "test",
    "Test description",
    "text/plain",
    fn(_context) {
      Ok(@resource.ResourceReadResult::text("test", uri="file:///test.txt"))
    },
  )
  let resource = registry.list_resources()[0]
  @debug.assert_eq(resource.description, Some("Test description"))
  @debug.assert_eq(resource.mime_type, Some("text/plain"))
}
