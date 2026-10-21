///| Host routing tests that do not require live transports.

///|
#cfg(not(target="wasm-gc"))
async test "MCPHost lists no tools without connections" {
  let host = MCPHost::MCPHost(name="host", version="1.0.0")
  try host.list_tools() catch {
    _ => panic()
  } noraise {
    result => @debug.assert_eq(result.tools.length(), 0)
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "MCPHost rejects unqualified tool names" {
  let host = MCPHost::MCPHost(name="host", version="1.0.0")
  try host.call_tool("echo") catch {
    @types.MCPError::_ as e =>
      @debug.assert_eq(
        e.message(),
        "Tool name must be qualified as '<connection>.<tool>'",
      )
    error => raise error
  } noraise {
    _ => panic()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "MCPHost reports missing named connection" {
  let host = MCPHost::MCPHost(name="host", version="1.0.0")
  try host.call_tool("local.echo") catch {
    @types.MCPError::_ as e =>
      @debug.assert_eq(e.message(), "Connection not found: local")
    error => raise error
  } noraise {
    _ => panic()
  }
}

///|
test "host aggregation retains source cache metadata and cursors without inventing aggregate freshness" {
  let metadata = @types.ResultMetadata::from_json(
    {
      "ttlMs": 500,
      "cacheScope": "private",
      "_meta": {
        "io.modelcontextprotocol/serverInfo": {
          "name": "source",
          "version": "1",
        },
      },
    },
    body_fields=[],
  )
  let tool = @types.ToolDefinition::new("echo", { "type": "object" })
  let result = aggregate_tool_lists(
    Map::from_array([
      ("local", { tools: [tool], next_cursor: Some("page2"), metadata, }),
    ]),
  )
  assert_eq(result.tools[0].name, "local.echo")
  assert_eq(tool.name, "echo")
  assert_eq(result.metadata.ttl_ms, None)
  assert_eq(result.metadata.cache_scope, None)
  assert_eq(
    result.metadata.extensions.get("dev.moonbit.mcp/hostSources"),
    Some(
      Json::object({
        "local": { "metadata": metadata.to_json(), "nextCursor": "page2" },
      }),
    ),
  )
}
