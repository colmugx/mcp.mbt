///| MCPServer - Main Server Implementation

///|=====================================================

///|
pub struct MCPServer {
  name : String
  version : String
  registry : ToolRegistry
  resource_registry : ResourceRegistry
  prompt_registry : PromptRegistry
}

///|
pub fn MCPServer::new(name : String, version : String) -> MCPServer {
  {
    name,
    version,
    registry: ToolRegistry::new(),
    resource_registry: ResourceRegistry::new(),
    prompt_registry: PromptRegistry::new(),
  }
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
pub fn MCPServer::register_resource(
  self : MCPServer,
  uri : String,
  name : String,
  description : String,
  mime_type : String,
  handler : async () -> Result[@resource.ResourceReadResult, @types.MCPError],
) -> Unit {
  self.resource_registry.register(uri, name, description, mime_type, handler)
}

///|
pub fn[T : @resource.Resource] MCPServer::register_trait_resource(
  self : MCPServer,
  resource : T,
) -> Unit {
  self.resource_registry.register_trait_resource(resource)
}

///|
pub fn MCPServer::register_prompt(
  self : MCPServer,
  name : String,
  description : String,
  arguments : Array[@types.PromptArgument],
  handler : async (Json) -> Result[@types.GetPromptResult, @types.MCPError],
) -> Unit {
  self.prompt_registry.register(name, description, arguments, handler)
}

///|
pub fn[T : @prompt.Prompt] MCPServer::register_trait_prompt(
  self : MCPServer,
  prompt : T,
) -> Unit {
  self.prompt_registry.register_trait_prompt(prompt)
}

///|
pub async fn MCPServer::notify_tools_list_changed(
  _ : MCPServer,
  transport : @transport.AnyTransport,
) -> Unit raise @types.TransportError {
  let notification = @types.tools_list_changed_notification()
  transport.send_notification(notification)
}

///|
pub async fn MCPServer::notify_resources_list_changed(
  _ : MCPServer,
  transport : @transport.AnyTransport,
) -> Unit raise @types.TransportError {
  let notification = @types.resources_list_changed_notification()
  transport.send_notification(notification)
}

///|
pub async fn MCPServer::notify_prompts_list_changed(
  _ : MCPServer,
  transport : @transport.AnyTransport,
) -> Unit raise @types.TransportError {
  let notification = @types.prompts_list_changed_notification()
  transport.send_notification(notification)
}

///|
pub fn handle_initialize(server : MCPServer, id : Int) -> String {
  let tools_cap = @internal.json_object([
    ("listChanged", @internal.json_bool(true)),
  ])
  let resources_cap = @internal.json_object([
    ("subscribe", @internal.json_bool(true)),
    ("listChanged", @internal.json_bool(true)),
  ])
  let prompts_cap = @internal.json_object([
    ("listChanged", @internal.json_bool(true)),
  ])
  let capabilities = @internal.json_object([
    ("tools", tools_cap),
    ("resources", resources_cap),
    ("prompts", prompts_cap),
  ])
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
fn handle_resources_list(server : MCPServer, id : Int) -> String {
  let resources = server.resource_registry.list_resources()
  let resource_jsons = resources.map(fn(resource) {
    @internal.json_object([
      ("uri", @internal.json_string(resource.uri)),
      ("name", @internal.json_string(resource.name)),
      (
        "description",
        resource.description.map(@internal.json_string).unwrap_or("null"),
      ),
    ])
  })
  let result = @internal.json_object([
    ("resources", @internal.json_array(resource_jsons)),
  ])
  @internal.jsonrpc_success(id, result)
}

///|
async fn handle_resources_read(
  server : MCPServer,
  id : Int,
  params : Json,
) -> String {
  let uri = @internal.extract_string_from_json(params, "uri")
  match uri {
    None => @internal.jsonrpc_error(id, -32602, "Missing 'uri' parameter")
    Some(uri_str) =>
      match server.resource_registry.read_resource(uri_str) {
        Ok(read_result) => {
          let content_json = match read_result.content {
            @resource.Text(text) =>
              @internal.json_object([
                ("uri", @internal.json_string(read_result.uri)),
                ("text", @internal.json_string(text)),
              ])
            @resource.Blob(data, mime_type~) =>
              @internal.json_object([
                ("uri", @internal.json_string(read_result.uri)),
                ("blob", @internal.json_string(data.to_string())),
                ("mimeType", @internal.json_string(mime_type)),
              ])
          }
          let result = @internal.json_object([
            ("contents", @internal.json_array([content_json])),
          ])
          @internal.jsonrpc_success(id, result)
        }
        Err(e) => @internal.jsonrpc_error(id, e.to_error_code(), e.message())
      }
  }
}

///|
fn handle_resources_subscribe(
  server : MCPServer,
  id : Int,
  params : Json,
) -> String {
  let uri = @internal.extract_string_from_json(params, "uri")
  match uri {
    None => @internal.jsonrpc_error(id, -32602, "Missing 'uri' parameter")
    Some(uri_str) =>
      match server.resource_registry.subscribe(uri_str) {
        Ok(_) => @internal.jsonrpc_success(id, @internal.json_object([]))
        Err(e) => @internal.jsonrpc_error(id, e.to_error_code(), e.message())
      }
  }
}

///|
fn handle_resources_unsubscribe(
  server : MCPServer,
  id : Int,
  params : Json,
) -> String {
  let uri = @internal.extract_string_from_json(params, "uri")
  match uri {
    None => @internal.jsonrpc_error(id, -32602, "Missing 'uri' parameter")
    Some(uri_str) =>
      match server.resource_registry.unsubscribe(uri_str) {
        Ok(_) => @internal.jsonrpc_success(id, @internal.json_object([]))
        Err(e) => @internal.jsonrpc_error(id, e.to_error_code(), e.message())
      }
  }
}

///|
fn handle_prompts_list(server : MCPServer, id : Int) -> String {
  let prompts = server.prompt_registry.list_prompts()
  let prompt_jsons = prompts.map(fn(prompt) {
    @internal.json_object([
      ("name", @internal.json_string(prompt.name)),
      (
        "description",
        prompt.description.map(@internal.json_string).unwrap_or("null"),
      ),
    ])
  })
  let result = @internal.json_object([
    ("prompts", @internal.json_array(prompt_jsons)),
  ])
  @internal.jsonrpc_success(id, result)
}

///|
async fn handle_prompts_get(
  server : MCPServer,
  id : Int,
  params : Json,
) -> String {
  let prompt_name = @internal.extract_string_from_json(params, "name")
  match prompt_name {
    None => @internal.jsonrpc_error(id, -32602, "Missing 'name' parameter")
    Some(name) =>
      match server.prompt_registry.get_prompt(name, params) {
        Ok(prompt_result) => {
          let messages_json = prompt_result.messages.map(fn(msg) {
            let content = match msg.content {
              @tool.Text(text) =>
                @internal.json_object([
                  ("type", @internal.json_string("text")),
                  ("text", @internal.json_string(text)),
                ])
              _ => "null" // Handle other content types if necessary
            }
            @internal.json_object([
              ("role", @internal.json_string(msg.role)),
              ("content", content),
            ])
          })
          let result = @internal.json_object([
            (
              "description",
              prompt_result.description
              .map(@internal.json_string)
              .unwrap_or("null"),
            ),
            ("messages", @internal.json_array(messages_json)),
          ])
          @internal.jsonrpc_success(id, result)
        }
        Err(e) => @internal.jsonrpc_error(id, e.to_error_code(), e.message())
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
        "resources/list" => handle_resources_list(self, request.id)
        "resources/read" =>
          handle_resources_read(self, request.id, request.params)
        "resources/subscribe" =>
          handle_resources_subscribe(self, request.id, request.params)
        "resources/unsubscribe" =>
          handle_resources_unsubscribe(self, request.id, request.params)
        "prompts/list" => handle_prompts_list(self, request.id)
        "prompts/get" => handle_prompts_get(self, request.id, request.params)
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

///|
pub fn[T : @tool.Tool] MCPServer::with_tool(
  self : MCPServer,
  tool : T,
) -> MCPServer {
  self.register_trait_tool(tool)
  self
}

///|
pub fn[T : @resource.Resource] MCPServer::with_resource(
  self : MCPServer,
  resource : T,
) -> MCPServer {
  self.register_trait_resource(resource)
  self
}

///|
pub fn[T : @prompt.Prompt] MCPServer::with_prompt(
  self : MCPServer,
  prompt : T,
) -> MCPServer {
  self.register_trait_prompt(prompt)
  self
}

///|
pub async fn MCPServer::run_stdio(
  self : MCPServer,
) -> Unit raise @types.TransportError {
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::new(),
  )
  self.run(transport)
}

///|
pub fn mcp_server(name~ : String, version~ : String) -> MCPServer {
  MCPServer::new(name, version)
}
