///| High-level MCP host over multiple named client connections.

///|
pub struct MCPHost {
  name : String
  version : String
  connections : Map[String, MCPClient]
}

///|
pub fn MCPHost::MCPHost(name~ : String, version~ : String) -> MCPHost {
  { name, version, connections: {}, }
}

///|
/// Register a named connection to a remote MCP server over HTTP. `era` is
/// passed through to `MCPClient::connect_http`:
///
/// | era    | `server/discover` probe | legacy fallback |
/// |--------|-------------------------|-----------------|
/// | Auto   | yes (default)           | allowed         |
/// | Legacy | skipped                 | direct connect  |
/// | Modern | yes                     | forbidden (Err) |
pub async fn MCPHost::connect_http(
  self : MCPHost,
  name~ : String,
  url~ : String,
  auth_token? : String = "",
  era? : ProtocolEra = Auto,
) -> Result[Unit, @types.MCPError] {
  match
    MCPClient::connect_http(
      url~,
      name=self.name + "/" + name,
      version=self.version,
      auth_token~,
      era~,
    ) {
    Ok(client) => {
      self.connections[name] = client
      Ok(())
    }
    Err(e) => Err(e)
  }
}

///|
/// Register a named connection to a spawned MCP server. `era` is passed
/// through to `MCPClient::connect_stdio` (same semantics table as
/// `MCPHost::connect_http`).
pub async fn MCPHost::connect_stdio(
  self : MCPHost,
  name~ : String,
  cmd~ : String,
  args? : Array[String] = [],
  extra_env? : Map[String, String] = {},
  group~ : @async.TaskGroup[Unit],
  era? : ProtocolEra = Auto,
) -> Result[Unit, @types.MCPError] {
  match
    MCPClient::connect_stdio(
      cmd~,
      args~,
      name=self.name + "/" + name,
      version=self.version,
      extra_env~,
      group~,
      era~,
    ) {
    Ok(client) => {
      self.connections[name] = client
      Ok(())
    }
    Err(e) => Err(e)
  }
}

///|
pub async fn MCPHost::list_tools(
  self : MCPHost,
) -> Result[ListToolsResult, @types.MCPError] {
  let results : Map[String, ListToolsResult] = Map([])
  for connection_name, client in self.connections {
    match client.list_tools() {
      Ok(result) => results.set(connection_name, result)
      Err(error) => return Err(error)
    }
  }
  Ok(aggregate_tool_lists(results))
}

///|
fn aggregate_tool_lists(
  results : Map[String, ListToolsResult],
) -> ListToolsResult {
  let tools : Array[@types.ToolDefinition] = []
  let sources : Map[String, Json] = Map([])
  for connection_name, result in results {
    for tool in result.tools {
      tools.push({ ..tool, name: connection_name + "." + tool.name, })
    }
    let source : Map[String, Json] = { "metadata": result.metadata.to_json() }
    match result.next_cursor {
      Some(cursor) => source.set("nextCursor", Json::string(cursor))
      None => ()
    }
    sources.set(connection_name, Json::object(source))
  }
  // Cache hints belong to each source, not to the synthetic aggregate.
  let metadata = @types.ResultMetadata::empty()
  metadata.extensions.set("dev.moonbit.mcp/hostSources", Json::object(sources))
  { tools, next_cursor: None, metadata, }
}

///|
pub async fn MCPHost::call_tool(
  self : MCPHost,
  qualified_name : String,
  arguments? : String = "{}",
) -> Result[CallToolResult, @types.MCPError] {
  match qualified_name.split_once(".") {
    Some((connection_view, tool_view)) => {
      let connection_name = connection_view.to_owned()
      let tool_name = tool_view.to_owned()
      match self.connections.get(connection_name) {
        Some(client) => client.call_tool(tool_name, arguments~)
        None =>
          Err(@types.MethodNotFound("Connection not found: " + connection_name))
      }
    }
    None =>
      Err(
        @types.InvalidRequest(
          "Tool name must be qualified as '<connection>.<tool>'",
        ),
      )
  }
}

///|
pub async fn MCPHost::close_all(self : MCPHost) -> Unit {
  for entry in self.connections {
    let (_, client) = entry
    client.close()
  }
  self.connections.clear()
}
