///|
async test "HTTP client close releases a receiver blocked on its response queue" {
  let transport = HttpClientTransport::HttpClientTransport(
    "http://example.invalid/mcp",
  )
  @async.with_task_group(group => {
    let receiver = group.spawn(() => transport.receive())
    @async.sleep(1)
    transport.close()
    assert_eq(@async.with_timeout(1000, () => receiver.wait()), None)
    transport.close()
  })
}

///|
async test "HTTP queue receive preserves runtime cancellation rather than reporting EOF" {
  let transport = HttpClientTransport::HttpClientTransport(
    "http://example.invalid/mcp",
  )
  defer transport.close()
  @async.with_task_group(group => {
    let cancelled = Ref(false)
    let receiver = group.spawn(() => {
      ignore(transport.receive()) catch {
        error => cancelled.val = @async.is_cancellation_error(error)
      }
    })
    @async.sleep(1)
    receiver.cancel()
    ignore(receiver.wait())
    assert_true(cancelled.val)
  })
}
