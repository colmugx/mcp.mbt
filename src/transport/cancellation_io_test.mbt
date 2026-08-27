///| Cancellation regression tests — native only (real sockets + @async
/// runtime). Regression (Phase 7): a `with_timeout` cancellation injected at
/// an HttpClientTransport suspension point used to be re-labeled by the
/// transport's error-translating catches (ReadError / WriteError), so callers
/// saw the wrong error identity and the timeout fallback could not recognize
/// it. The catches now re-raise whenever `@async.is_being_cancelled()`.
///
/// Stall-server mode: the listener accepts but never responds, so the send
/// either times out or hangs forever — there is no tight timing to race
/// against, only the generous `with_timeout` bound.

///|
/// Accept one connection and park forever without writing anything.
async fn stall_after_accept(server : @socket.TcpServer) -> Unit {
  let (conn, _addr) = server.accept()
  // Hold the connection open without ever writing a response.
  ignore(conn)
  @async.sleep(3_600_000)
}

///|
async test "timeout during send surfaces TimeoutError, not ReadError" {
  let server = try! @socket.TcpServer::TcpServer(
    @socket.Addr::parse("127.0.0.1:47341"),
    reuse_addr=true,
  )
  defer server.close()
  @async.with_task_group(group => {
    // Explicit cancel before group exit: with_task_group waits for children
    // to terminate naturally, so a parked stall task must be cancelled by
    // hand or the group never returns (same pattern as sse_flush_io_test).
    let stall_task = group.spawn(async fn() { stall_after_accept(server) })
    let client = HttpClientTransport::HttpClientTransport(
      "http://127.0.0.1:47341/",
    )
    // Cancellation lands in the end_request catch (the P6 hit point); before
    // the fix it escaped as ReadError("Failed to get response: Cancelled").
    try
      @async.with_timeout(5000, async fn() {
        client.send("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}")
      })
    catch {
      e =>
        if e is @async.TimeoutError {
          ()
        } else {
          fail("expected TimeoutError, got translated error: \{e}")
        }
    } noraise {
      _ => fail("send unexpectedly completed against a stalling server")
    }
    stall_task.cancel()
  })
}

///|
/// Semantic anchor: the error carried by a cancelled task is exactly what
/// `@async.is_cancellation_error` recognizes — the property the enclosing
/// task-group timeout fallback relies on once translation catches stop
/// swallowing cancellations.
async test "cancelled task error is recognized by is_cancellation_error" {
  @async.with_task_group(group => {
    let sleeper = group.spawn(async fn() { @async.sleep(3_600_000) })
    sleeper.cancel()
    try {
      let _ = sleeper.wait()
      let _ : Unit = fail("cancelled task completed normally")
    } catch {
      e =>
        if @async.is_cancellation_error(e) {
          ()
        } else {
          fail("cancellation error not recognized: \{e}")
        }
    } noraise {
      _ => fail("wait on cancelled task did not raise")
    }
  })
}

///|
/// Group-boundary regression (the exact P6 failure shape): cancelling a
/// running `send` directly — no `with_timeout` involved — must surface a
/// recognizable cancellation error to the joining group, not a ReadError.
async test "direct send cancellation keeps identity at group boundary" {
  let server = try! @socket.TcpServer::TcpServer(
    @socket.Addr::parse("127.0.0.1:47342"),
    reuse_addr=true,
  )
  defer server.close()
  let entered : @async.Queue[Unit] = @async.Queue(kind=Unbounded)
  @async.with_task_group(group => {
    let stall_task = group.spawn(async fn() { stall_after_accept(server) })
    let client = HttpClientTransport::HttpClientTransport(
      "http://127.0.0.1:47342/",
    )
    let send_task = group.spawn(async fn() {
      // Signal entry so cancel can only fire once the send is already in
      // flight; otherwise the task dies before reaching the transport.
      entered.put(())
      client.send("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}")
    })
    let _ = entered.get()
    // No timing race: the send cannot complete against the stall server, so
    // cancelling is the only exit path.
    send_task.cancel()
    try {
      let _ = send_task.wait()
      let _ : Unit = fail("cancelled send completed normally")
    } catch {
      e =>
        if @async.is_cancellation_error(e) {
          ()
        } else {
          fail("send cancellation lost its identity: \{e}")
        }
    } noraise {
      _ => fail("wait on cancelled send did not raise")
    }
    stall_task.cancel()
  })
}
