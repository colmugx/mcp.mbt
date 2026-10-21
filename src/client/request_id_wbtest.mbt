///|
async test "response routing isolates string ids and adjacent integers beyond binary64" {
  let transport = @transport.HttpClientTransport::HttpClientTransport(
    "http://unused.invalid",
  )
  defer transport.close()
  let client = MCPClient::MCPClient(
    name="test",
    version="1",
    transport=@transport.AnyTransport::HttpClient(transport),
  )
  let ids = [
    @types.RequestId::from_json(@validation.parse_json("9007199254740992")),
    @types.RequestId::from_json(@validation.parse_json("9007199254740993")),
    @types.RequestId::Str("9007199254740993"),
    @types.RequestId::Int(42),
  ]
  let queues : Array[@aqueue.Queue[String]] = []
  for id in ids {
    let queue : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
    client.response_map.set(id.key(), queue)
    queues.push(queue)
  }
  transport.pending_responses.put(
    "{\"jsonrpc\":\"2.0\",\"id\":42.1,\"result\":{}}",
  )
  for index in [3, 2, 1, 0] {
    let id = if index == 3 { "4.200e1" } else { ids[index].to_json_string() }
    transport.pending_responses.put(
      "{\"jsonrpc\":\"2.0\",\"id\":" +
      id +
      ",\"result\":{\"marker\":" +
      index.to_string() +
      "}}",
    )
  }
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => client.pump_direct_responses(group))
  })
  for index, queue in queues {
    let response = @validation.parse_json(queue.try_get().unwrap())
    guard response is { "result": { "marker": Number(marker, ..), .. }, .. } else {
      fail("missing correlated response")
    }
    assert_eq(marker.to_int(), index)
  }
  assert_true(client.response_map.is_empty())
}

///|
async test "raw requests reject invalid ids and canonical duplicates before transport IO" {
  let transport = @transport.HttpClientTransport::HttpClientTransport(
    "http://unused.invalid",
  )
  defer transport.close()
  let client = MCPClient::MCPClient(
    name="test",
    version="1",
    transport=@transport.AnyTransport::HttpClient(transport),
  )
  for id in ["null", "true", "1.5", "1.00000000000000000001"] {
    try
      client.send_request(
        "{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"method\":\"tools/list\"}",
      )
    catch {
      @types.InvalidRequest(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected protocol error")
    }
  }
  try
    client.send_request("{\"jsonrpc\":\"2.0\",\"method\":\"tools/list\"}")
  catch {
    @types.InvalidRequest(_) => ()
    error => raise error
  } noraise {
    _ => fail("expected protocol error")
  }
  assert_true(client.request_cancellations.is_empty())
  assert_true(client.response_map.is_empty())
  let key = @types.RequestId::Int(42).key()
  let cancelled = Ref(false)
  client.request_cancellations.set(key, fn(_) { cancelled.val = true })
  try
    client.send_request(
      "{\"jsonrpc\":\"2.0\",\"id\":4.2e1,\"method\":\"tools/list\"}",
    )
  catch {
    @types.InvalidRequest(_) => ()
    error => raise error
  } noraise {
    _ => fail("expected protocol error")
  }
  assert_true(client.request_cancellations.contains(key))
  assert_false(cancelled.val)
  assert_eq(client.cancel_request(@types.RequestId::Int(42)), ())
  assert_true(cancelled.val)
  client.request_cancellations.clear()
}

///|
test "subscription and cancellation notifications keep numeric and string identity distinct" {
  for literal in ["9007199254740993", "\"9007199254740993\"", "4.2e1"] {
    let id = @types.RequestId::from_json(@validation.parse_json(literal))
    let params = @validation.parse_json("{\"requestId\":" + literal + "}")
    guard params is Object(fields) else { fail("expected object") }
    assert_eq(parse_cancelled_notification(fields).unwrap().request_id, id)
    let tagged = @validation.parse_json(
      "{\"_meta\":{\"io.modelcontextprotocol/subscriptionId\":" + literal + "}}",
    )
    assert_eq(extract_subscription_id(Some(tagged)), Some(id.key()))
  }
  assert_eq(parse_cancelled_notification({ "requestId": 42.1 }), None)
}

///|
test "era probes do not alias large or fractional error codes to modern reserved codes" {
  for code in ["4294935276", "-32020.00000000000000000001", "1e1000"] {
    assert_true(
      parse_jsonrpc_error(
        "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":" +
        code +
        ",\"message\":\"not a header mismatch\"}}",
      )
      is None,
    )
  }
  assert_true(
    parse_jsonrpc_error(
      "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32020,\"message\":\"mismatch\"}}",
    )
    is Some(@types.HeaderMismatch(_)),
  )
}
