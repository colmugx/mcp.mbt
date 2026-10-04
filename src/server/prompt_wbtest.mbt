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
  registry.register_simple("test_prompt", "Test prompt description", [], fn(
    _context,
    _args,
  ) {
    Ok(@types.GetPromptResult::new([], description="Test"))
  })
  @debug.assert_eq(registry.list_prompts().length(), 1)
  @debug.assert_eq(registry.list_prompts()[0].name, "test_prompt")
}

///|
test "PromptRegistry::list_prompts returns prompt definitions" {
  let registry = PromptRegistry::PromptRegistry()
  registry.register_simple("prompt1", "First prompt", [], fn(_context, _args) {
    Ok(@types.GetPromptResult::new([], description="Test1"))
  })
  registry.register_simple("prompt2", "Second prompt", [], fn(_context, _args) {
    Ok(@types.GetPromptResult::new([], description="Test2"))
  })
  let prompts = registry.list_prompts()
  @debug.assert_eq(prompts.length(), 2)
}

///|
test "PromptRegistry::list_prompts includes description" {
  let registry = PromptRegistry::PromptRegistry()
  registry.register_simple("test", "Test description", [], fn(_context, _args) {
    Ok(@types.GetPromptResult::new([], description="Test"))
  })
  let prompt = registry.list_prompts()[0]
  @debug.assert_eq(prompt.description, Some("Test description"))
}

///|
test "PromptRegistry::list_prompts includes arguments" {
  let registry = PromptRegistry::PromptRegistry()
  registry.register_simple(
    "test",
    "Test",
    [@types.PromptArgument::new("arg1", description="First arg", required=true)],
    fn(_context, _args) {
      Ok(@types.GetPromptResult::new([], description="Test"))
    },
  )
  let prompts = registry.list_prompts()
  match prompts[0].arguments {
    Some(args) => @debug.assert_eq(args.length(), 1)
    None => fail("Expected arguments")
  }
}
