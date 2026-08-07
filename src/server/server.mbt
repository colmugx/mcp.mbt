///| MCPServer - Main Server Implementation

///|
priv enum ReplyHandle {
  Stdio(@aqueue.Queue[String])
  Http(@async.Queue[String])
}

///|
priv struct ServerRequest {
  message : String
  reply : ReplyHandle
}

///|
async fn ReplyHandle::send(
  self : ReplyHandle,
  response : String,
) -> Unit raise @types.TransportError {
  match self {
    Stdio(queue) =>
      queue.put(response) catch {
        e => raise @types.WriteError(e.to_string())
      }
    Http(queue) =>
      queue.put(response) catch {
        e => raise @types.WriteError(e.to_string())
      }
  }
}

///|
pub struct MCPServer {
  name : String
  version : String
  title : String?
  description : String?
  instructions : String?
  auth_config : @transport.AuthConfig?
  registry : ToolRegistry
  resource_registry : ResourceRegistry
  prompt_registry : PromptRegistry
}

///|
pub fn MCPServer::MCPServer(name : String, version : String) -> MCPServer {
  {
    name,
    version,
    title: None,
    description: None,
    instructions: None,
    auth_config: None,
    registry: ToolRegistry::ToolRegistry(),
    resource_registry: ResourceRegistry::ResourceRegistry(),
    prompt_registry: PromptRegistry::PromptRegistry(),
  }
}

///|
fn MCPServer::register_tool(
  self : MCPServer,
  name : String,
  description : String,
  input_schema : Json,
  handler : async (Json) -> Result[@tool.ToolResult, @types.MCPError],
) -> Unit {
  self.registry.register(name, description, input_schema, handler)
}

///|
fn[T : @tool.Tool] MCPServer::register_trait_tool(
  self : MCPServer,
  tool : T,
) -> Unit {
  self.registry.register_trait_tool(tool)
}

///|
fn MCPServer::register_resource(
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
fn[T : @resource.Resource] MCPServer::register_trait_resource(
  self : MCPServer,
  resource : T,
) -> Unit {
  self.resource_registry.register_trait_resource(resource)
}

///|
fn MCPServer::register_prompt(
  self : MCPServer,
  name : String,
  description : String,
  arguments : Array[@types.PromptArgument],
  handler : async (Json) -> Result[@types.GetPromptResult, @types.MCPError],
) -> Unit {
  self.prompt_registry.register(name, description, arguments, handler)
}

///|
fn[T : @prompt.Prompt] MCPServer::register_trait_prompt(
  self : MCPServer,
  prompt : T,
) -> Unit {
  self.prompt_registry.register_trait_prompt(prompt)
}

///|
pub async fn MCPServer::handle_request(
  self : MCPServer,
  request_json : String,
) -> String {
  match parse_request_message(request_json) {
    Ok(request) => self.handle_parsed_request(request)
    Err(response) => response
  }
}

///|
fn parse_request_message(
  request_json : String,
) -> Result[@types.JsonRpcRequest, String] {
  let parsed = @json.parse(request_json) catch {
    _ =>
      return Err(
        jsonrpc_error_str(@types.RequestId::Int(0), -32700, "Parse error"),
      )
  }
  match @types.JsonRpcRequest::from_json(parsed) {
    Ok(request) => Ok(request)
    Err(e) =>
      Err(
        jsonrpc_error_str(
          @types.RequestId::Int(0),
          e.to_error_code(),
          e.message(),
        ),
      )
  }
}

///|
fn is_fast_method(method_name : String) -> Bool {
  method_name == "tools/list" ||
  method_name == "resources/list" ||
  method_name == "prompts/list"
}

///|
async fn MCPServer::handle_parsed_request(
  self : MCPServer,
  request : @types.JsonRpcRequest,
) -> String {
  match request.method_name {
    "tools/list" => handle_tools_list(self, request.id)
    "tools/call" => handle_tools_call(self, request.id, request.params)
    "resources/list" => handle_resources_list(self, request.id)
    "resources/read" => handle_resources_read(self, request.id, request.params)
    "prompts/list" => handle_prompts_list(self, request.id)
    "prompts/get" => handle_prompts_get(self, request.id, request.params)
    _ =>
      jsonrpc_error_str(
        request.id,
        -32601,
        "Method not found: " + request.method_name,
      )
  }
}

///|
fn internal_error_response(id : @types.RequestId) -> String {
  jsonrpc_error_str(id, -32603, "Internal server error")
}

///|
async fn MCPServer::handle_server_request(
  self : MCPServer,
  request : ServerRequest,
  group : @async.TaskGroup[Unit],
) -> Unit {
  match parse_request_message(request.message) {
    Err(response) => request.reply.send(response) catch { _ => () }
    Ok(parsed_request) =>
      if is_fast_method(parsed_request.method_name) {
        let response = self.handle_parsed_request(parsed_request) catch {
          _ => internal_error_response(parsed_request.id)
        }
        request.reply.send(response) catch {
          _ => ()
        }
      } else {
        group.spawn_bg(() => {
          let response = self.handle_parsed_request(parsed_request) catch {
            _ => internal_error_response(parsed_request.id)
          }
          request.reply.send(response) catch {
            _ => ()
          }
        })
      }
  }
}

///|
async fn MCPServer::run_stdio_transport(
  self : MCPServer,
  transport : @transport.StdioTransport,
  group : @async.TaskGroup[Unit],
) -> Unit raise @types.TransportError {
  let response_queue : @aqueue.Queue[String] = @aqueue.Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  group.spawn_bg(() => {
    while true {
      let response = response_queue.get() catch { _ => break }
      transport.send(response) catch {
        _ => ()
      }
    }
  })

  while true {
    match transport.receive() {
      None => {
        response_queue.close()
        transport.close()
        break
      }
      Some(message) =>
        self.handle_server_request(
          { message, reply: ReplyHandle::Stdio(response_queue) },
          group,
        ) catch {
          _ => ()
        }
    }
  }
}

///|
async fn MCPServer::run_http_transport(
  self : MCPServer,
  transport : @transport.HttpTransport,
  group : @async.TaskGroup[Unit],
) -> Unit raise @types.TransportError {
  while true {
    match transport.receive_request() {
      None => {
        transport.close()
        break
      }
      Some((message, reply_queue)) =>
        self.handle_server_request(
          { message, reply: ReplyHandle::Http(reply_queue) },
          group,
        ) catch {
          _ => ()
        }
    }
  }
}

///|
async fn MCPServer::run_with_transport(
  self : MCPServer,
  transport : @transport.AnyTransport,
  group : @async.TaskGroup[Unit],
) -> Unit raise @types.TransportError {
  match transport {
    Stdio(stdio) => self.run_stdio_transport(stdio, group)
    Http(http) => self.run_http_transport(http, group)
    _ =>
      raise @types.InvalidState(
        "MCPServer::run requires a server transport (stdio or http)",
      )
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
pub fn MCPServer::tool(
  self : MCPServer,
  name : String,
  description : String,
  input_schema : Json,
  handler : async (Json) -> Result[@tool.ToolResult, @types.MCPError],
) -> MCPServer {
  self.register_tool(name, description, input_schema, handler)
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
pub fn MCPServer::resource(
  self : MCPServer,
  uri : String,
  name : String,
  description : String,
  mime_type : String,
  handler : async () -> Result[@resource.ResourceReadResult, @types.MCPError],
) -> MCPServer {
  self.register_resource(uri, name, description, mime_type, handler)
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
pub fn MCPServer::prompt(
  self : MCPServer,
  name : String,
  description : String,
  arguments : Array[@types.PromptArgument],
  handler : async (Json) -> Result[@types.GetPromptResult, @types.MCPError],
) -> MCPServer {
  self.register_prompt(name, description, arguments, handler)
  self
}

///|
pub fn MCPServer::with_title(self : MCPServer, title : String) -> MCPServer {
  { ..self, title: Some(title) }
}

///|
pub fn MCPServer::with_description(
  self : MCPServer,
  description : String,
) -> MCPServer {
  { ..self, description: Some(description) }
}

///|
pub fn MCPServer::with_instructions(
  self : MCPServer,
  instructions : String,
) -> MCPServer {
  { ..self, instructions: Some(instructions) }
}

///|
pub fn MCPServer::with_auth(
  self : MCPServer,
  auth : @transport.AuthConfig,
) -> MCPServer {
  { ..self, auth_config: Some(auth) }
}

///|
pub async fn MCPServer::run_stdio(
  self : MCPServer,
) -> Unit raise @types.TransportError {
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::StdioTransport(),
  )
  @async.with_task_group(group => self.run_with_transport(transport, group)) catch {
    e => raise @types.ReadError("TaskGroup error: " + e.to_string())
  }
}

///|
pub async fn MCPServer::run_http(
  self : MCPServer,
  port? : Int = 4240,
  path? : String = "/mcp",
) -> Unit raise @types.TransportError {
  @async.with_task_group(group => {
    let http = @transport.HttpTransport::HttpTransport(
      port~,
      endpoint_path=path,
    )
    let http = match self.auth_config {
      Some(auth) => http.with_auth(auth)
      None => http
    }
    group.spawn_bg(async fn() { http.start() })
    let transport = @transport.AnyTransport::Http(http)
    self.run_with_transport(transport, group)
  }) catch {
    e => raise @types.ReadError("TaskGroup error: " + e.to_string())
  }
}

///|
pub fn mcp_server(name~ : String, version~ : String) -> MCPServer {
  MCPServer::MCPServer(name, version)
}
