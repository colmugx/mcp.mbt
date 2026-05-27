///| Prompt Registry Tests

///| PromptRegistry basic functionality

///|
test "PromptRegistry::new creates empty registry" {
  let registry = PromptRegistry::new()
  assert_eq(registry.list_prompts().length(), 0)
}

///|
test "PromptRegistry::register adds prompt entry" {
  let registry = PromptRegistry::new()
  registry.register("test_prompt", "Test prompt description", [], async fn(
    _args,
  ) {
    Ok({ description: Some("Test"), messages: [] })
  })
  assert_eq(registry.list_prompts().length(), 1)
  assert_eq(registry.list_prompts()[0].name, "test_prompt")
}

///|
test "PromptRegistry::list_prompts returns prompt definitions" {
  let registry = PromptRegistry::new()
  registry.register("prompt1", "First prompt", [], async fn(_args) {
    Ok({ description: Some("Test1"), messages: [] })
  })
  registry.register("prompt2", "Second prompt", [], async fn(_args) {
    Ok({ description: Some("Test2"), messages: [] })
  })
  let prompts = registry.list_prompts()
  assert_eq(prompts.length(), 2)
}

///|
test "PromptRegistry::list_prompts includes description" {
  let registry = PromptRegistry::new()
  registry.register("test", "Test description", [], async fn(_args) {
    Ok({ description: Some("Test"), messages: [] })
  })
  let prompt = registry.list_prompts()[0]
  assert_eq(prompt.description, Some("Test description"))
}

///|
test "PromptRegistry::list_prompts includes arguments" {
  let registry = PromptRegistry::new()
  registry.register(
    "test",
    "Test",
    [{ name: "arg1", description: Some("First arg"), required: Some(true) }],
    async fn(_args) { Ok({ description: Some("Test"), messages: [] }) },
  )
  let prompts = registry.list_prompts()
  match prompts[0].arguments {
    Some(args) => assert_eq(args.length(), 1)
    None => fail("Expected arguments")
  }
}
