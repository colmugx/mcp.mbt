///|
test "cancellation is idempotent and disposed callbacks do not run" {
  let token = @runtime.CancellationToken::new()
  let calls = Ref(0)
  let disposed = token.on_cancel(fn() { calls.val += 100 })
  disposed.dispose()
  let active = token.on_cancel(fn() { calls.val += 1 })
  token.cancel()
  token.cancel()
  assert_eq(calls.val, 1)
  assert_true(token.is_cancelled())
  active.dispose()
  ignore(token.on_cancel(fn() { calls.val += 10 }))
  assert_eq(calls.val, 11)
  try token.throw_if_cancelled() catch {
    @runtime.RequestCancelled => ()
  } noraise {
    _ => fail("cancelled work must stop")
  }
}

///|
test "request context copies runtime maps without modifying arguments" {
  let meta : Map[String, Json] = { "trace": "a" }
  let responses : Map[String, Json] = { "input": { "action": "accept" } }
  let context = @runtime.RequestContext::new(
    @types.RequestId::Int(7),
    meta~,
    input_responses=responses,
    continuation_state={ "step": 2 },
    principal=@runtime.Principal::new("user", scopes=["read"]),
  )
  meta.set("trace", "changed")
  responses.clear()
  assert_eq(context.meta.get("trace"), Some(Json::string("a")))
  assert_true(context.input_responses.contains("input"))
  assert_eq(context.principal.map(fn(p) { p.id }), Some("user"))
  assert_eq(context.continuation_state, Some(Json::object({ "step": 2 })))
}
