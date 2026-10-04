///|
async test "concurrent large stdio requests and notifications retain whole newline frames" {
  @async.with_task_group(group => {
    let transport = @transport.StdioClientTransport::StdioClientTransport(
      cmd="cat",
    )
    transport.start(group)
    defer transport.close()
    let payload = "x".repeat(20000)
    let first : Json = {
      "jsonrpc": "2.0",
      "id": 1,
      "method": "tools/call",
      "params": { "name": "first", "arguments": { "payload": payload } },
    }
    let second : Json = {
      "jsonrpc": "2.0",
      "id": 2,
      "method": "tools/call",
      "params": { "name": "second", "arguments": { "payload": payload } },
    }
    let notification : @types.Notification = {
      method_name: "notifications/cancelled",
      params: Some(Json::object({ "requestId": 1, "payload": payload })),
    }
    let frames : Array[Json] = []
    let reader = group.spawn(() => {
      for _ in 0..<3 {
        let message = transport.receive().unwrap()
        frames.push(@json.parse(message))
      }
    })
    let write_first = group.spawn(() => transport.send(first.stringify()))
    let write_second = group.spawn(() => transport.send(second.stringify()))
    let write_notification = group.spawn(() => {
      transport.send_notification(notification)
    })
    @async.with_timeout(5000, () => reader.wait())
    write_first.wait()
    write_second.wait()
    write_notification.wait()
    assert_eq(frames.length(), 3)
    assert_true(frames.contains(first))
    assert_true(frames.contains(second))
    assert_true(frames.contains(@json.parse(notification.to_jsonrpc_string())))
  })
}
