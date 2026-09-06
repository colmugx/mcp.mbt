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
            // requestId is the string form of the internal Int request id.
            assert_eq(params.get("requestId"), Some(Json::string("7")))
          _ => fail("cancelled notification has no params object")
        }
      }
      _ => fail("echoed notification is not a JSON object")
    }
  })
}
