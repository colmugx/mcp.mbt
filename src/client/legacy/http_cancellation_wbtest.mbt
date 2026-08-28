///| LegacyHttpSessionTransport cancellation regression tests — native only.
/// Regression: the session transport's error-translating catches
/// used to re-label a `with_timeout` / task-group cancellation injected at an
/// HTTP suspension point as WriteError/ReadError, hiding the cancellation
/// identity from callers. They now re-raise when
/// `@async.is_being_cancelled()` (see http_session.mbt).
///
/// Stall-server mode: accept one connection and never respond, so the send
/// either times out or hangs forever — no tight timing involved.

///|
/// Accept one connection and park forever without writing anything.
async fn stall_after_accept_legacy(server : @socket.TcpServer) -> Unit {
  let (conn, _addr) = server.accept()
  ignore(conn)
  @async.sleep(3_600_000)
}

///|
async test "timeout during legacy send surfaces TimeoutError, not ReadError" {
  let server = try! @socket.TcpServer::TcpServer(
    @socket.Addr::parse("127.0.0.1:47345"),
    reuse_addr=true,
  )
  defer server.close()
  let transport = LegacyHttpSessionTransport::LegacyHttpSessionTransport(
    url="http://127.0.0.1:47345/",
    auth_token="",
  )
  @async.with_task_group(group => {
    // Explicit cancel before group exit: with_task_group waits for children
    // to terminate naturally, so a parked stall task must be cancelled by
    // hand or the group never returns.
    let stall_task = group.spawn(async fn() {
      stall_after_accept_legacy(server)
    })
    // Cancellation lands in the do_post end_request catch; before the fix it
    // escaped as ReadError("Failed to get response: Cancelled").
    try
      @async.with_timeout(5000, async fn() {
        transport.send("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}")
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
/// Group-boundary regression: cancelling a running legacy send directly must
/// surface a recognizable cancellation error to the joining group, not a
/// translated ReadError.
async test "direct legacy send cancellation keeps identity at group boundary" {
  let server = try! @socket.TcpServer::TcpServer(
    @socket.Addr::parse("127.0.0.1:47346"),
    reuse_addr=true,
  )
  defer server.close()
  let transport = LegacyHttpSessionTransport::LegacyHttpSessionTransport(
    url="http://127.0.0.1:47346/",
    auth_token="",
  )
  let entered : @async.Queue[Unit] = @async.Queue(kind=Unbounded)
  @async.with_task_group(group => {
    let stall_task = group.spawn(async fn() {
      stall_after_accept_legacy(server)
    })
    let send_task = group.spawn(async fn() {
      // Signal entry so cancel can only fire once the send is already in
      // flight; otherwise the task dies before reaching the transport.
      entered.put(())
      transport.send("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}")
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
