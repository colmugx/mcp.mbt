///|
async test "registry raises handler errors without changing their wire identity" {
  let registry = ToolRegistry::ToolRegistry()
  let expected = @types.InvalidParams("handler rejected input")
  registry.register("reject", "Reject", { "type": "object" }, (_context, _) => {
    Err(expected)
  })
  try
    registry.call_tool(
      "reject",
      @runtime.RequestContext::new(@types.RequestId::Int(1)),
      {},
    )
  catch {
    @types.MCPError::_ as error =>
      assert_eq(error.to_jsonrpc_error(), expected.to_jsonrpc_error())
    error => raise error
  } noraise {
    _ => fail("expected the handler error to be raised")
  }
}

///|
async test "registry cancellation takes precedence over a returned handler error" {
  let registry = ToolRegistry::ToolRegistry()
  registry.register("cancel", "Cancel", { "type": "object" }, (context, _) => {
    context.cancellation_token.cancel()
    Err(@types.InvalidParams("must not replace cancellation"))
  })
  try
    registry.call_tool(
      "cancel",
      @runtime.RequestContext::new(@types.RequestId::Int(1)),
      {},
    )
  catch {
    @runtime.RequestCancelled => ()
    error => raise error
  } noraise {
    _ => fail("expected request cancellation")
  }
}
