///|
async test "temporary client pump routes out-of-order replies and progress without an event loop" {
  let transport = @transport.HttpClientTransport::HttpClientTransport(
    "http://unused.invalid",
  )
  let progress : Array[Double] = []
  let client = MCPClient::MCPClient(
    name="test",
    version="1",
    transport=@transport.AnyTransport::HttpClient(transport),
  ).on_notification({
    ..NotificationHandlers::empty(),
    on_progress: Some(fn(notification) { progress.push(notification.progress) }),
  })
  let first : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  let second : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  client.response_map.set(@types.RequestId::Int(1).key(), first)
  client.response_map.set(@types.RequestId::Int(2).key(), second)
  transport.pending_responses.put(
    Json::object({
      "jsonrpc": "2.0",
      "method": "notifications/progress",
      "params": { "progressToken": 7.5, "progress": 0.5 },
    }).stringify(),
  )
  transport.pending_responses.put(
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"marker\":\"second\"}}",
  )
  transport.pending_responses.put(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"marker\":\"first\"}}",
  )
  @async.with_task_group(group => client.pump_direct_responses(group))
  assert_eq(progress, [0.5])
  assert_true(
    @json.parse(first.get())
    is { "id": Number(1, ..), "result": { "marker": String("first"), .. }, .. },
  )
  assert_true(
    @json.parse(second.get())
    is { "id": Number(2, ..), "result": { "marker": String("second"), .. }, .. },
  )
  assert_true(client.response_map.is_empty())
  assert_false(client.event_loop_started)
  transport.close()
}

///|
async test "temporary client pump closes pending queues on transport EOF" {
  let transport = @transport.HttpClientTransport::HttpClientTransport(
    "http://unused.invalid",
  )
  let client = MCPClient::MCPClient(
    name="test",
    version="1",
    transport=@transport.AnyTransport::HttpClient(transport),
  )
  let queue : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  client.response_map.set(@types.RequestId::Int(1).key(), queue)
  transport.close()
  @async.with_task_group(group => client.pump_direct_responses(group))
  assert_true(client.response_map.is_empty())
  try queue.get() catch {
    _ => ()
  } noraise {
    _ => fail("EOF must release pending response waits")
  }
}

///|
#cfg(any(target="native", target="js", target="wasm"))
async test "best effort cancellation notification has a bounded serialized-writer wait" {
  let transport = @transport.StdioClientTransport::StdioClientTransport(
    cmd="cat",
  )
  transport.send_mutex.acquire()
  defer transport.send_mutex.release()
  let client = MCPClient::MCPClient(
    name="test",
    version="1",
    transport=@transport.AnyTransport::StdioClient(transport),
  )
  let started = @async.now()
  client.notify_cancelled_best_effort(@types.RequestId::Int(1), wait_ms=50)
  let elapsed = @async.now() - started
  assert_true(elapsed >= 45 && elapsed < 1500)
}
