///| send_request cancellation tests — native only (real child process +
/// @async runtime). Regression: task cancellation injected while a request
/// waited for its response used to be swallowed into
/// InternalError("Receive failed"); it now re-raises after a best-effort
/// `notifications/cancelled` reaches the server. The `sh -c 'read x; cat'`
/// child consumes the request line (so the client waits in receive) and then
/// echoes the abort notification back on stdout, making it observable through
/// the still-usable transport.

///|
/// Settled inside the spawned task: a cancelled task that dies with a
/// non-cancellation error would fail the task group, so the raise is caught
/// where it happens (same probe pattern as the ext-mcp e2e suite).
priv struct SendRequestProbe {
  mut raised : Bool
}

///|
async test "cancelled send_request re-raises and delivers notifications/cancelled" {
  @async.with_task_group(group => {
    let transport = @transport.StdioClientTransport::StdioClientTransport(
      cmd="sh",
      args=["-c", "read x; cat"],
    )
    transport.start(group) catch {
      _ => fail("could not start child process")
    }
    defer transport.close()
    let client = MCPClient::MCPClient(
      name="t",
      version="1",
      transport=@transport.AnyTransport::StdioClient(transport),
    )
    let request = "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/list\",\"params\":{}}"
    let probe = SendRequestProbe::{ raised: false, }
    let task : @async.Task[Unit] = group.spawn(() => {
      let _ : Result[String, @types.MCPError] = client.send_request(request) catch {
        _ => {
          probe.raised = true
          Err(@types.InternalError("placeholder, never inspected"))
        }
      }
    })
    // Let the child consume the request line first, so the task is
    // deterministically blocked in receive when the cancellation lands.
    @async.sleep(300)
    task.cancel()
    let _ = task.wait()
    assert_true(probe.raised)
    // The shielded abort notification must have reached the child; `cat`
    // echoes it back and the transport stays usable.
    let echoed = @async.with_timeout(3000, async fn() { transport.receive() }) catch {
      e => fail("no echoed notification arrived: \{e}")
    }
    let echoed_line = match echoed {
      Some(line) => line
      None => fail("transport closed before the notification echo")
    }
    let msg = @json.parse(echoed_line) catch {
      _ => fail("echoed line is not JSON: " + echoed_line)
    }
    match msg {
      Object(fields) => {
        assert_eq(fields["method"], "notifications/cancelled")
        match fields.get("params") {
          Some(Object(params)) =>
            // Numeric request ids must stay numeric to match the server's in-flight task.
            assert_eq(params.get("requestId"), Some(Json::number(7)))
          _ => fail("cancelled notification has no params object")
        }
      }
      _ => fail("echoed notification is not a JSON object")
    }
  })
}

///|
async test "explicit stdio cancellation releases local wait and preserves numeric id and reason" {
  @async.with_task_group(group => {
    let transport = @transport.StdioClientTransport::StdioClientTransport(
      cmd="sh",
      args=["-c", "read x; cat"],
    )
    transport.start(group)
    defer transport.close()
    let client = MCPClient::MCPClient(
      name="t",
      version="1",
      transport=@transport.AnyTransport::StdioClient(transport),
    )
    let task = group.spawn(() => {
      client.send_request(
        "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/list\",\"params\":{}}",
      )
    })
    @async.sleep(300)
    assert_true(client.request_cancellations.contains(8))
    assert_eq(
      client.cancel_request(@types.RequestId::Int(8), reason="user stop"),
      Ok(()),
    )
    match @async.with_timeout(3000, () => task.wait()) {
      Err(@types.Cancelled(_)) => ()
      _ => fail("explicit cancellation must release the local request wait")
    }
    assert_false(client.request_cancellations.contains(8))
    assert_false(client.response_map.contains(8))
    let echoed = @async.with_timeout(3000, () => transport.receive()).unwrap()
    let message = @json.parse(echoed)
    guard message
      is {
        "params": {
          "requestId": Number(8, ..),
          "reason": String("user stop"),
          ..
        },
        ..
      } else {
      fail("cancelled notification must retain numeric id and reason")
    }
  })
}

///|
async test "explicit HTTP cancellation closes the owned request stream and releases the caller" {
  let server = @socket.TcpServer(
    @socket.Addr::parse("127.0.0.1:47334"),
    reuse_addr=true,
  )
  defer server.close()
  let started : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
  let disconnected : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
  let transport = @transport.HttpClientTransport::HttpClientTransport(
    "http://127.0.0.1:47334/mcp",
  )
  let client = MCPClient::MCPClient(
    name="t",
    version="1",
    transport=@transport.AnyTransport::HttpClient(transport),
  )
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (connection, _) = server.accept()
      defer connection.close()
      let head = connection.read_until("\r\n\r\n").unwrap()
      assert_true(head.to_lower().contains("transfer-encoding: chunked"))
      ignore(connection.read_until("\r\n0\r\n\r\n").unwrap())
      connection.write(
        "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\nd\r\n: keepalive\n\n\r\n",
      )
      started.put(())
      let remaining = connection.read_some()
      assert_true(
        remaining is None,
        msg="unexpected request bytes: \{Repr(remaining)}, head: \{head}",
      )
      disconnected.put(())
    })
    let task = group.spawn(() => {
      client.send_request(
        "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/list\",\"params\":{}}",
      )
    })
    ignore(@async.with_timeout(3000, () => started.get()))
    assert_true(client.request_cancellations.contains(9))
    assert_eq(client.cancel_request(@types.RequestId::Int(9)), Ok(()))
    match @async.with_timeout(3000, () => task.wait()) {
      Err(@types.Cancelled(_)) => ()
      _ => fail("HTTP cancellation must release the caller")
    }
    ignore(@async.with_timeout(3000, () => disconnected.get()))
  })
  assert_true(client.request_cancellations.is_empty())
}

///|
async test "closing the client cancels its owned stdio request and releases the caller" {
  @async.with_task_group(group => {
    let transport = @transport.StdioClientTransport::StdioClientTransport(
      cmd="sh",
      args=["-c", "read x; cat"],
    )
    transport.start(group)
    defer transport.close()
    let client = MCPClient::MCPClient(
      name="t",
      version="1",
      transport=@transport.AnyTransport::StdioClient(transport),
    )
    let task = group.spawn(() => {
      client.send_request(
        "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/list\",\"params\":{}}",
      )
    })
    @async.sleep(300)
    assert_true(client.request_cancellations.contains(10))
    client.close()
    match @async.with_timeout(3000, () => task.wait()) {
      Err(@types.Cancelled(_)) => ()
      result => fail("closing client must release request: \{Repr(result)}")
    }
    assert_true(client.request_cancellations.is_empty())
  })
}

///|
async test "direct HTTP calls consume progress then their own response without poisoning the next call" {
  let server = @socket.TcpServer(
    @socket.Addr::parse("127.0.0.1:47336"),
    reuse_addr=true,
  )
  defer server.close()
  let progress : Array[Double] = []
  let transport = @transport.HttpClientTransport::HttpClientTransport(
    "http://127.0.0.1:47336/mcp",
  )
  let client = MCPClient::MCPClient(
    name="test",
    version="1",
    transport=@transport.AnyTransport::HttpClient(transport),
  ).on_notification({
    ..NotificationHandlers::empty(),
    on_progress: Some(fn(notification) { progress.push(notification.progress) }),
  })
  defer client.close()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      for id in [1, 2] {
        let (connection, _) = server.accept()
        defer connection.close()
        ignore(connection.read_until("\r\n\r\n").unwrap())
        ignore(connection.read_until("\r\n0\r\n\r\n").unwrap())
        let notification = Json::object({
          "jsonrpc": "2.0",
          "method": "notifications/progress",
          "params": { "progressToken": 7.5, "progress": id },
        }).stringify()
        let response = Json::object({
          "jsonrpc": "2.0",
          "id": id,
          "result": { "resultType": "complete", "marker": id },
        }).stringify()
        let body = ": heartbeat\n\ndata: " +
          notification +
          "\n\ndata: " +
          response +
          "\n\n"
        connection.write(
          "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: " +
          @utf8.encode(body).length().to_string() +
          "\r\nConnection: close\r\n\r\n" +
          body,
        )
      }
    })
    for id in [1, 2] {
      let request = Json::object({
        "jsonrpc": "2.0",
        "id": id,
        "method": "tools/list",
        "params": {},
      }).stringify()
      let response = @async.with_timeout(3000, () => {
        client.send_request(request)
      }).unwrap()
      let result = parse_jsonrpc_response(response).unwrap()
      assert_true(
        result is Object(fields) &&
        fields.get("marker") == Some(Json::number(id.to_double())),
      )
      assert_false(client.event_loop_started)
    }
  })
  assert_eq(progress, [1.0, 2.0])
  assert_true(client.response_map.is_empty())
  assert_true(client.request_cancellations.is_empty())
}

///|
async test "concurrent direct HTTP calls correlate out-of-order replies independently" {
  let server = @socket.TcpServer(
    @socket.Addr::parse("127.0.0.1:47337"),
    reuse_addr=true,
  )
  defer server.close()
  let transport = @transport.HttpClientTransport::HttpClientTransport(
    "http://127.0.0.1:47337/mcp",
  )
  let client = MCPClient::MCPClient(
    name="test",
    version="1",
    transport=@transport.AnyTransport::HttpClient(transport),
  )
  defer client.close()
  let first_started : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
  let second_consumed : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
  let request1 = Json::object({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list",
    "params": {},
  }).stringify()
  let request2 = Json::object({
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {},
  }).stringify()
  let response1 = Json::object({
    "jsonrpc": "2.0",
    "id": 1,
    "result": { "marker": "first" },
  }).stringify()
  let response2 = Json::object({
    "jsonrpc": "2.0",
    "id": 2,
    "result": { "marker": "second" },
  }).stringify()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (first, _) = server.accept()
      defer first.close()
      ignore(first.read_until("\r\n\r\n").unwrap())
      ignore(first.read_until("\r\n0\r\n\r\n").unwrap())
      first_started.put(())
      let (second, _) = server.accept()
      defer second.close()
      ignore(second.read_until("\r\n\r\n").unwrap())
      ignore(second.read_until("\r\n0\r\n\r\n").unwrap())
      second.write(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " +
        @utf8.encode(response2).length().to_string() +
        "\r\nConnection: close\r\n\r\n" +
        response2,
      )
      second_consumed.get()
      first.write(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " +
        @utf8.encode(response1).length().to_string() +
        "\r\nConnection: close\r\n\r\n" +
        response1,
      )
    })
    let first = group.spawn(() => client.send_request(request1))
    @async.with_timeout(3000, () => first_started.get())
    let second = group.spawn(() => client.send_request(request2))
    assert_eq(@async.with_timeout(3000, () => second.wait()), Ok(response2))
    second_consumed.put(())
    assert_eq(@async.with_timeout(3000, () => first.wait()), Ok(response1))
  })
  assert_true(client.response_map.is_empty())
  assert_true(client.request_cancellations.is_empty())
}
