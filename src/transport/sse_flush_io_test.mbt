///| SSE flush regression tests — native only (real sockets + @async runtime).
/// Regression (Phase 2.5): the server-side SSE response branch must flush the
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
  let transport = HttpTransport::HttpTransport(port=47331, endpoint_path="/mcp")
  let client = HttpClientTransport::HttpClientTransport(
    "http://127.0.0.1:47331/mcp",
  )
  let ack_seen = @async.Queue(kind=Blocking(1))
  let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"subscriptions/listen\",\"params\":{}}"
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
