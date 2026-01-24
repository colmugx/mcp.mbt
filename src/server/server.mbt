///|
pub struct MCPServer {
  name : String
  version : String
  registry : ToolRegistry
}

///|
pub fn MCPServer::new(name : String, version : String) -> MCPServer {
  { name, version, registry: ToolRegistry::new() }
}

///|
pub fn MCPServer::register_tool(
  self : MCPServer,
  name : String,
  description : String,
  input_schema : Json,
  handler : async (Json) -> Result[@tool.ToolResult, @types.MCPError],
) -> Unit {
  self.registry.register(name, description, input_schema, handler)
}

///|
pub fn[T : @tool.Tool] MCPServer::register_trait_tool(
  self : MCPServer,
  tool : T,
) -> Unit {
  self.registry.register_trait_tool(tool)
}

///|
fn handle_initialize(server : MCPServer, id : Int) -> String {
  let tools_cap = @internal.json_object([
    ("listChanged", @internal.json_bool(true)),
  ])
  let capabilities = @internal.json_object([("tools", tools_cap)])
  let server_info = @internal.json_object([
    ("name", @internal.json_string(server.name)),
    ("version", @internal.json_string(server.version)),
  ])
  let result = @internal.json_object([
    ("protocolVersion", @internal.json_string("2025-06-18")),
    ("capabilities", capabilities),
    ("serverInfo", server_info),
  ])
  @internal.jsonrpc_success(id, result)
}

///|
fn handle_tools_list(server : MCPServer, id : Int) -> String {
  let tools = server.registry.list_tools()
  let tool_jsons = tools.map(fn(tool) {
    @internal.json_object([
      ("name", @internal.json_string(tool.name)),
      ("description", @internal.json_string(tool.description)),
      ("inputSchema", tool.input_schema.stringify()),
    ])
  })
  let result = @internal.json_object([
    ("tools", @internal.json_array(tool_jsons)),
  ])
  @internal.jsonrpc_success(id, result)
}

///|
async fn handle_tools_call(
  server : MCPServer,
  id : Int,
  params : Json,
) -> String {
  let tool_name = @internal.extract_string_from_json(params, "name")
  match tool_name {
    None => @internal.jsonrpc_error(id, -32602, "Missing 'name' parameter")
    Some(name) => {
      let arguments = if params is Object(obj) {
        obj.get("arguments").unwrap_or(null)
      } else {
        null
      }
      match server.registry.call_tool(name, arguments) {
        Ok(tool_result) => {
          let content_items = tool_result.content.map(fn(item) {
            match item {
              @tool.Text(text) =>
                @internal.json_object([
                  ("type", @internal.json_string("text")),
                  ("text", @internal.json_string(text)),
                ])
              @tool.Image(data, mime_type~) =>
                @internal.json_object([
                  ("type", @internal.json_string("image")),
                  ("data", @internal.json_string(data)),
                  ("mimeType", @internal.json_string(mime_type)),
                ])
              @tool.Resource(uri) =>
                @internal.json_object([
                  ("type", @internal.json_string("resource")),
                  ("uri", @internal.json_string(uri)),
                ])
            }
          })
          let result = @internal.json_object([
            ("content", @internal.json_array(content_items)),
            ("isError", @internal.json_bool(tool_result.is_error)),
          ])
          @internal.jsonrpc_success(id, result)
        }
        Err(e) => @internal.jsonrpc_error(id, e.to_error_code(), e.message())
      }
    }
  }
}

///|
pub async fn MCPServer::handle_request(
  self : MCPServer,
  request_json : String,
) -> String {
  let parsed = @json.parse(request_json) catch {
    _ => return @internal.jsonrpc_error(0, -32700, "Parse error")
  }
  match @types.JsonRpcRequest::from_json(parsed) {
    Err(e) => @internal.jsonrpc_error(0, e.to_error_code(), e.message())
    Ok(request) =>
      match request.method_name {
        "initialize" => handle_initialize(self, request.id)
        "tools/list" => handle_tools_list(self, request.id)
        "tools/call" => handle_tools_call(self, request.id, request.params)
        _ =>
          @internal.jsonrpc_error(
            request.id,
            -32601,
            "Method not found: " + request.method_name,
          )
      }
  }
}

///|
pub async fn MCPServer::run(
  self : MCPServer,
  transport : @transport.AnyTransport,
) -> Unit raise @types.TransportError {
  while true {
    match transport.receive() {
      None => {
        transport.close()
        break
      }
      Some(message) => {
        let response = self.handle_request(message) catch {
          _ => @internal.jsonrpc_error(0, -32603, "Internal server error")
        }
        transport.send(response)
      }
    }
  }
}
