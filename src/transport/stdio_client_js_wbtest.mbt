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
test "stdio client: streaming capability matches native" {
  let transport = StdioClientTransport::StdioClientTransport(cmd="unused")
  inspect(transport.supports_streaming(), content="false")
  transport.send_event(event_type="ignored", data="ignored")
}
