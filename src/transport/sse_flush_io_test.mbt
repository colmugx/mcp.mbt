///| SSE flush regression tests — native only (real sockets + @async runtime).
/// Regression: the server-side SSE response branch must flush the
/// response headers and each event as it is written; buffering until
/// `end_response` starves long-lived streams entirely.

///|
/// Block until a TCP connect to `addr` succeeds. Connection-refused means the
/// HttpTransport server task has not bound its port yet; the deadline turns
/// "never binds" into a bounded failure instead of a hung test.
async fn wait_for_listen(addr : @socket.Addr, timeout_ms? : Int = 5000) -> Unit {
  let deadline = @async.now() + timeout_ms.to_int64()
  while true {
    let probe = Some(@socket.Tcp::connect(addr)) catch { _ => None }
    match probe {
      Some(tcp) => {
        tcp.close()
        return
      }
      None =>
        if @async.now() > deadline {
          fail("server did not bind within \{timeout_ms}ms")
        } else {
          @async.sleep(20)
        }
    }
  }
}

///|
/// The server-side app answers one request with a notification (switching the
/// transport into SSE mode), then withholds the final response until the
/// client confirms via `ack_seen` that the notification actually arrived.
///
/// Not time-sensitive: with a flush regression the first event never reaches
/// the wire, the app stays blocked on `ack_seen`, and the 3s timeout fails
/// the test — a deadlock, not a race. On the happy path every hop is
/// loopback-local (milliseconds), so the generous timeout only trips on a
/// real regression.
async test "HttpTransport SSE stream delivers events before end_response" {
  let transport = @transport.HttpTransport::HttpTransport(
    port=47331,
    endpoint_path="/mcp",
  )
  let client = @transport.HttpClientTransport::HttpClientTransport(
    "http://127.0.0.1:47331/mcp",
  )
  let ack_seen = @async.Queue(kind=Blocking(1))
  // Requests must carry params._meta (protocolVersion + clientCapabilities)
  // or the server rejects the POST with 400 before it reaches the app.
  let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"subscriptions/listen\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{}}}}"
  let first_event = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/message\",\"params\":{\"progress\":50}}"
  let final_response = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"done\":true}}"
  @async.with_task_group(group => {
    // Server-side application: notification first, final response only after
    // the client has received it.
    group.spawn_bg(async fn() {
      match transport.receive_request() {
        Some((_message, reply)) => {
          reply.put(first_event) catch {
            _ => ()
          }
          ack_seen.get() catch {
            _ => ()
          }
          reply.put(final_response) catch {
            _ => ()
          }
        }
        None => fail("transport produced no request")
      }
    })
    // HTTP server; teardown errors (cancellation) are swallowed so the task
    // never fails the group at cleanup time.
    let server_task = group.spawn(async fn() {
      transport.start() catch {
        _ => ()
      }
    })
    wait_for_listen(@socket.Addr::parse("127.0.0.1:47331"))
    // Client POST parks on the SSE response; events surface via receive().
    group.spawn_bg(async fn() { client.send(request) catch { _ => () } })
    match @async.with_timeout_opt(3000, async fn() { client.receive() }) {
      Some(Some(event)) => @debug.assert_eq(event, first_event)
      _ => fail("first SSE event never arrived while stream was open")
    }
    ack_seen.put(())
    match @async.with_timeout_opt(3000, async fn() { client.receive() }) {
      Some(Some(event)) => @debug.assert_eq(event, final_response)
      _ => fail("final response never arrived after ack handshake")
    }
    server_task.cancel()
  })
}

///|
async test "SSE disconnect cancels its authenticated envelope and server stays alive" {
  let transport = @transport.HttpTransport::HttpTransport(
    port=47333,
    keepalive_interval_ms=10,
  ).with_auth(
    @transport.AuthConfig(
      authenticate=fn(token) {
        if token == "valid" {
          Some(@runtime.Principal::new("alice", scopes=["read"]))
        } else {
          None
        }
      },
      resource_metadata_url="http://127.0.0.1:47333/.well-known/oauth-protected-resource",
    ),
  )
  let client = @transport.HttpClientTransport::HttpClientTransport(
    "http://127.0.0.1:47333/mcp",
    auth_token="valid",
  )
  let cancelled : @async.Queue[Unit] = @async.Queue(kind=Unbounded)
  let retained : Ref[@transport.AuthenticatedRequest?] = Ref(None)
  let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"subscriptions/listen\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{}}}}"
  let first = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/message\",\"params\":{}}"
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let envelope = transport.receive_authenticated_request().unwrap()
      assert_eq(envelope.principal.map(fn(p) { p.id }), Some("alice"))
      retained.val = Some(envelope)
      ignore(
        envelope.cancellation_token.on_cancel(fn() {
          ignore(cancelled.try_put(()) catch { _ => false })
        }),
      )
      envelope.reply.put(first)
      let next = transport.receive_authenticated_request().unwrap()
      next.reply.put(
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"resultType\":\"complete\"}}",
      )
    })
    let server_task = group.spawn(() => transport.start() catch { _ => () })
    wait_for_listen(@socket.Addr::parse("127.0.0.1:47333"))
    let sender = group.spawn(() => {
      client.send(request) catch {
        error => if !@async.is_cancellation_error(error) { raise error }
      }
    })
    match @async.with_timeout_opt(3000, () => client.receive()) {
      Some(Some(event)) => assert_eq(event, first)
      _ => fail("SSE first event did not arrive")
    }
    sender.cancel()
    match @async.with_timeout_opt(3000, () => cancelled.get()) {
      Some(_) => ()
      None => fail("disconnected SSE request was not cancelled")
    }
    let envelope = retained.val.unwrap()
    assert_true(envelope.cancellation_token.is_cancelled())
    try envelope.reply.try_put("late") catch {
      _ => ()
    } noraise {
      _ => fail("disconnected reply queue must be closed")
    }
    let next_client = @transport.HttpClientTransport::HttpClientTransport(
      "http://127.0.0.1:47333/mcp",
      auth_token="valid",
    )
    next_client.send(request.replace(old="\"id\":1", new="\"id\":2"))
    assert_true(next_client.receive() is Some(_))
    server_task.cancel()
  })
}
