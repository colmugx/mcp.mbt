///|
/// A legacy MCP exchange is a single request followed by a receive on the same
/// transport. Concurrent callers must never read the underlying stdio pipe at
/// the same time: MoonBit async's PipeRead allows only one outstanding reader.
extern "js" fn legacy_test_node_path() -> String =
  #| () => globalThis.process.execPath

///|
/// Delay each echo so that two requests overlap unless the client explicitly
/// serializes the entire send/receive exchange (serializing writes alone is
/// insufficient). Each response is exactly the received JSON-RPC request.
let legacy_delayed_echo_script : String =
  #|let pending = '';
  #|process.stdin.on('data', (chunk) => {
  #|  pending += chunk.toString();
  #|  let end;
  #|  while ((end = pending.indexOf('\\n')) >= 0) {
  #|    const line = pending.slice(0, end);
  #|    pending = pending.slice(end + 1);
  #|    if (line.trim()) {
  #|      setTimeout(() => process.stdout.write(line + '\\n'), 150);
  #|    }
  #|  }
  #|});
  #|process.stdin.on('end', () => process.exit(0));

///|
async test "legacy stdio serializes concurrent send_raw calls and preserves response ids" {
  let stdio = @transport.StdioClientTransport::StdioClientTransport(
    cmd=legacy_test_node_path(),
    args=["-e", legacy_delayed_echo_script],
  )
  @async.with_task_group(group => {
    stdio.start(group)
    defer stdio.close()
    let client = LegacyClient::LegacyClient(
      name="legacy-concurrent-test",
      version="1",
      transport=@transport.AnyTransport::StdioClient(stdio),
    )
    let first_request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}"
    let second_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}"

    let first = group.spawn(() => client.send_raw(first_request), allow_failure=true)
    // The first request has entered read_until and is waiting for the child.
    // Before the fix, the second concurrent receive hit PipeRead's guard!.
    @async.sleep(25)
    let second = group.spawn(() => client.send_raw(second_request), allow_failure=true)

    let first_response = @async.with_timeout(5000, () => first.wait())
    let second_response = @async.with_timeout(5000, () => second.wait())
    inspect(first_response, content=first_request)
    inspect(second_response, content=second_request)
  })
}
