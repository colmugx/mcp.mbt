///| Host routing tests that do not require live transports.

///|
async test "MCPHost lists no tools without connections" {
  let host = MCPHost::MCPHost(name="host", version="1.0.0")
  match host.list_tools() {
    Ok(result) => @debug.assert_eq(result.tools.length(), 0)
    Err(_) => panic()
  }
}

///|
async test "MCPHost rejects unqualified tool names" {
  let host = MCPHost::MCPHost(name="host", version="1.0.0")
  match host.call_tool("echo") {
    Err(e) =>
      @debug.assert_eq(
        e.message(),
        "Tool name must be qualified as '<connection>.<tool>'",
      )
    Ok(_) => panic()
  }
}

///|
async test "MCPHost reports missing named connection" {
  let host = MCPHost::MCPHost(name="host", version="1.0.0")
  match host.call_tool("local.echo") {
    Err(e) => @debug.assert_eq(e.message(), "Connection not found: local")
    Ok(_) => panic()
  }
}
