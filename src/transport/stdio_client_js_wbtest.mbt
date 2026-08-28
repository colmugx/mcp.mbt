///|
/// js-only integration tests for the real StdioClientTransport
/// (stdio_client_js.mbt): spawn a real `node -e` NDJSON echo child and
/// drive start → send → receive → graceful close (stdin EOF → exit 0).
/// These tests spawn processes; keep generous timeouts, no tight timing.

///|
/// NDJSON echo child: echoes every non-empty line back to stdout and
/// exits 0 when stdin reaches EOF.
let echo_script : String =
  #|let buf = ''
  #|process.stdin.on('data', (d) => {
  #|  buf += d
  #|  let i
  #|  while ((i = buf.indexOf('\n')) >= 0) {
  #|    const line = buf.slice(0, i)
  #|    buf = buf.slice(i + 1)
  #|    if (line.trim()) process.stdout.write(line + '\n')
  #|  }
  #|})
  #|process.stdin.on('end', () => process.exit(0))

///|
/// The node binary running this very test (works under `moon test
/// --target js` without PATH assumptions).
extern "js" fn node_exec_path() -> String =
  #| () => globalThis.process.execPath

///|
async test "stdio client: send/receive round-trip and graceful close" {
  let transport = StdioClientTransport::StdioClientTransport(
    cmd=node_exec_path(),
    args=["-e", echo_script],
  )
  @async.with_task_group(group => {
    transport.start(group)
    let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"test/echo\",\"params\":{}}"
    transport.send(request)
    match @async.with_timeout_opt(10000, async fn() { transport.receive() }) {
      Some(Some(line)) => inspect(line, content=request)
      _ => fail("expected echo line, got EOF or timeout")
    }
    // Capture the pre-registered exit promise before close() clears it,
    // then verify the graceful close: stdin EOF -> child exit code 0.
    let exit = transport.exit
    transport.close()
    match exit {
      Some(promise) =>
        match @async.with_timeout_opt(10000, async fn() { promise.wait() }) {
          Some(exit_info) => inspect(exit_info.code, content="0")
          None => fail("child did not exit within 10s of stdin EOF")
        }
      None => fail("transport did not expose an exit promise")
    }
  })
}

///|
async test "stdio client: state contract after close and on invalid use" {
  let transport = StdioClientTransport::StdioClientTransport(
    cmd=node_exec_path(),
    args=["-e", echo_script],
  )
  // close before start: no child, no crash
  transport.close()
  match @async.with_timeout_opt(1000, async fn() { transport.receive() }) {
    Some(None) => ()
    _ => fail("receive after close must return None")
  }
  try transport.send("{}") catch {
    @types.InvalidState(_) => ()
    e => fail("expected InvalidState, got \{e}")
  } noraise {
    _ => fail("send after close must raise InvalidState")
  }
  // send before start on a live transport
  let fresh = StdioClientTransport::StdioClientTransport(cmd=node_exec_path())
  try fresh.send("{}") catch {
    @types.InvalidState(_) => ()
    e => fail("expected InvalidState, got \{e}")
  } noraise {
    _ => fail("send before start must raise InvalidState")
  }
  // invalid JSON-RPC payload on a started transport
  @async.with_task_group(group => fresh.start(group))
  try fresh.send("not-json") catch {
    @types.WriteError(_) => ()
    e => fail("expected WriteError, got \{e}")
  } noraise {
    _ => fail("invalid JSON-RPC message must raise WriteError")
  }
  fresh.close()
  // double start on a live transport
  let twice = StdioClientTransport::StdioClientTransport(cmd=node_exec_path(), args=[
    "-e", echo_script,
  ])
  @async.with_task_group(group => twice.start(group))
  try @async.with_task_group(group => twice.start(group)) catch {
    @types.InvalidState(_) => ()
    e => fail("expected InvalidState, got \{e}")
  } noraise {
    _ => fail("double start must raise InvalidState")
  }
  twice.close()
}

///|
/// Group cancellation must terminate the child: a member task raising fails
/// the whole group, which cancels the spawned watchdog; the watchdog then
/// performs the graceful close (stdin EOF + 5s kill timer) and blocks until
/// the child is really gone, so `with_task_group` returns with no leaked
/// child process. Echo child stays alive forever without stdin EOF, so the
/// only way its exit promise can settle is the watchdog's intervention.
async test "stdio client: task group cancellation terminates the child" {
  let transport = StdioClientTransport::StdioClientTransport(
    cmd=node_exec_path(),
    args=["-e", echo_script],
  )
  let failed_as_expected = @async.with_timeout_opt(8000, async fn() {
    try {
      @async.with_task_group(group => {
        transport.start(group)
        group.spawn_bg(() => {
          @async.sleep(300)
          raise @types.InvalidState("cancel the group on purpose")
        })
        // Park the main task; the group failure tears it down with the
        // rest of the group, triggering the watchdog's cleanup path.
        @async.sleep(8000)
      })
      false
    } catch {
      @types.InvalidState(_) => true
      e => fail("group failed with unexpected error: \{e}")
    }
  })
  match failed_as_expected {
    Some(true) => ()
    Some(false) => fail("group finished without the expected cancellation")
    None => fail("group teardown hung past 8s (watchdog deadlocked?)")
  }
  // The child is really gone: its pre-registered exit promise has settled
  // (code 0 = graceful stdin-EOF exit; -1 = killed by the 5s timer).
  match transport.exit {
    Some(promise) =>
      match @async.with_timeout_opt(5000, async fn() { promise.wait() }) {
        Some(exit_info) =>
          assert_true(
            exit_info.code == 0 || exit_info.code == -1,
            msg="child must exit gracefully (0) or be killed (-1), got \{exit_info.code}",
          )
        None => fail("child still alive 5s after group cancellation")
      }
    None => fail("transport lost its exit promise")
  }
}

///|
/// A child that exits on its own (nonzero code included) ends the watchdog
/// normally: the task completes without failing the group, and the group
/// tears down cleanly. Exit-code semantics belong to receive()'s EOF
/// handling, not to the watchdog.
async test "stdio client: self-exiting child ends the watchdog without failing the group" {
  let transport = StdioClientTransport::StdioClientTransport(
    cmd=node_exec_path(),
    args=["-e", "setTimeout(() => process.exit(3), 150)"],
  )
  try {
    match
      @async.with_timeout_opt(8000, async fn() {
        @async.with_task_group(group => {
          transport.start(group)
          // Park past the child's self-exit: the finished watchdog must
          // neither fail nor hang the group at teardown.
          @async.sleep(1000)
        })
        true
      }) {
      Some(true) => ()
      _ => fail("group did not complete after child self-exit")
    }
  } catch {
    e => fail("group must not fail when the child exits by itself: \{e}")
  }
  match transport.exit {
    Some(promise) =>
      match @async.with_timeout_opt(5000, async fn() { promise.wait() }) {
        Some(exit_info) => inspect(exit_info.code, content="3")
        None => fail("exit promise did not settle after child self-exit")
      }
    None => fail("transport lost its exit promise")
  }
}

///|
test "stdio client: streaming capability matches native" {
  let transport = StdioClientTransport::StdioClientTransport(cmd="unused")
  inspect(transport.supports_streaming(), content="false")
  transport.send_event(event_type="ignored", data="ignored")
}
