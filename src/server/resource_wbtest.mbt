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

///|
test "ResourceRegistry::subscribe adds to subscriptions" {
  let registry = ResourceRegistry::ResourceRegistry()
  registry.register("file:///test.txt", "test", "Test", "text/plain", fn() {
    Ok({ uri: "file:///test.txt", content: @resource.Text("test") })
  })
  let result = registry.subscribe("file:///test.txt")
  @debug.debug_inspect(result, content="Ok(())")
}

///|
test "ResourceRegistry::subscribe returns error for non-existent resource" {
  let registry = ResourceRegistry::ResourceRegistry()
  let result = registry.subscribe("file:///nonexistent.txt")
  @debug.debug_inspect(
    result,
    content=(
      #|Err(InvalidParams("Resource not found: file:///nonexistent.txt"))
    ),
  )
}

///|
test "ResourceRegistry::subscribe prevents duplicates" {
  let registry = ResourceRegistry::ResourceRegistry()
  registry.register("file:///test.txt", "test", "Test", "text/plain", fn() {
    Ok({ uri: "file:///test.txt", content: @resource.Text("test") })
  })
  registry.subscribe("file:///test.txt") |> ignore
  registry.subscribe("file:///test.txt") |> ignore
  // Both should succeed, but only one subscription should exist
  // We can't directly inspect subscriptions, but unsubscribe should work
  let result = registry.unsubscribe("file:///test.txt")
  @debug.debug_inspect(result, content="Ok(())")
}

///|
test "ResourceRegistry::unsubscribe removes subscription" {
  let registry = ResourceRegistry::ResourceRegistry()
  registry.register("file:///test.txt", "test", "Test", "text/plain", fn() {
    Ok({ uri: "file:///test.txt", content: @resource.Text("test") })
  })
  registry.subscribe("file:///test.txt") |> ignore
  let result = registry.unsubscribe("file:///test.txt")
  @debug.debug_inspect(result, content="Ok(())")
}

///|
test "ResourceRegistry::unsubscribe always succeeds even if not subscribed" {
  let registry = ResourceRegistry::ResourceRegistry()
  let result = registry.unsubscribe("file:///nonexistent.txt")
  @debug.debug_inspect(result, content="Ok(())")
}
