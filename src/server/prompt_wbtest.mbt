///| Prompt Registry Tests

///| PromptRegistry basic functionality

///|
test "PromptRegistry::PromptRegistry creates empty registry" {
  let registry = PromptRegistry::PromptRegistry()
  @debug.assert_eq(registry.list_prompts().length(), 0)
}

///|
test "PromptRegistry::register adds prompt entry" {
  let registry = PromptRegistry::PromptRegistry()
  registry.register("test_prompt", "Test prompt description", [], fn(_args) {
    Ok({ description: Some("Test"), messages: [] })
  })
  @debug.assert_eq(registry.list_prompts().length(), 1)
  @debug.assert_eq(registry.list_prompts()[0].name, "test_prompt")
}

///|
test "PromptRegistry::list_prompts returns prompt definitions" {
  let registry = PromptRegistry::PromptRegistry()
  registry.register("prompt1", "First prompt", [], fn(_args) {
    Ok({ description: Some("Test1"), messages: [] })
  })
  registry.register("prompt2", "Second prompt", [], fn(_args) {
    Ok({ description: Some("Test2"), messages: [] })
  })
  let prompts = registry.list_prompts()
  @debug.assert_eq(prompts.length(), 2)
}

///|
test "PromptRegistry::list_prompts includes description" {
  let registry = PromptRegistry::PromptRegistry()
  registry.register("test", "Test description", [], fn(_args) {
    Ok({ description: Some("Test"), messages: [] })
  })
  let prompt = registry.list_prompts()[0]
  @debug.assert_eq(prompt.description, Some("Test description"))
}

///|
test "PromptRegistry::list_prompts includes arguments" {
  let registry = PromptRegistry::PromptRegistry()
  registry.register(
    "test",
    "Test",
    [{ name: "arg1", description: Some("First arg"), required: Some(true) }],
    fn(_args) { Ok({ description: Some("Test"), messages: [] }) },
  )
  let prompts = registry.list_prompts()
  match prompts[0].arguments {
    Some(args) => @debug.assert_eq(args.length(), 1)
    None => fail("Expected arguments")
  }
}
