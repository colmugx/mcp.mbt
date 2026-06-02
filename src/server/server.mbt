///| MCPServer - Main Server Implementation

///|=====================================================

///|
pub struct MCPServer {
  name : String
  version : String
  title : String?
  description : String?
  instructions : String?
  mut log_level : String?
  auth_config : @transport.AuthConfig?
  registry : ToolRegistry
  resource_registry : ResourceRegistry
  prompt_registry : PromptRegistry
}

///|
pub fn MCPServer::new(name : String, version : String) -> MCPServer {
  {
    name,
    version,
    title: None,
    description: None,
    instructions: None,
    log_level: None,
    auth_config: None,
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
pub async fn MCPServer::handle_request(
  self : MCPServer,
  request_json : String,
) -> String {
  let parsed = @json.parse(request_json) catch {
    _ =>
      return @jsonutil.jsonrpc_error(
        @types.RequestId::Int(0),
        -32700,
        "Parse error",
      )
  }
  match @types.JsonRpcRequest::from_json(parsed) {
    Err(e) =>
      @jsonutil.jsonrpc_error(
        @types.RequestId::Int(0),
        e.to_error_code(),
        e.message(),
      )
    Ok(request) =>
      match request.method_name {
        "initialize" => handle_initialize(self, request.id)
        "ping" => handle_ping(request.id)
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
        "logging/setLevel" => handle_set_level(self, request.id, request.params)
        _ =>
          @jsonutil.jsonrpc_error(
            request.id,
            -32601,
            "Method not found: " + request.method_name,
          )
      }
  }
}

///|
/// Determine if a request is a "fast" operation that doesn't need async spawning.
/// Fast requests are those that:
/// - Don't perform I/O operations
/// - Complete in microseconds (e.g., initialize, tools/list, resources/list)
/// - Don't benefit from concurrency
fn is_fast_request(message : String) -> Bool {
  message.contains("\"method\":\"initialize\"") ||
  message.contains("\"method\":\"ping\"") ||
  message.contains("\"method\":\"tools/list\"") ||
  message.contains("\"method\":\"resources/list\"") ||
  message.contains("\"method\":\"prompts/list\"")
}

///|
pub async fn MCPServer::run(
  self : MCPServer,
  transport : @transport.AnyTransport,
  group : @async.TaskGroup[Unit],
) -> Unit raise @types.TransportError {
  // 创建响应队列用于并发任务到发送任务的通信
  let response_queue : @aqueue.Queue[String] = @aqueue.Queue(
    kind=@aqueue.Kind::Unbounded,
  )

  // 生成发送任务：专门负责从队列取响应并发送
  group.spawn_bg(fn() {
    while true {
      let response = response_queue.get() catch {
        _ => break // 队列关闭时退出
      }
      transport.send(response) catch {
        _ => () // 忽略发送错误，继续处理
      }
    }
  })

  // 主循环：接收请求并为每个请求生成并发任务
  while true {
    match transport.receive() {
      None => {
        response_queue.close() // 关闭队列通知发送任务退出
        transport.close()
        break
      }
      Some(message) =>
        // 性能优化：快速请求直接执行，避免spawn开销
        if is_fast_request(message) {
          // 快速路径：直接执行，不spawn新协程
          let response = self.handle_request(message) catch {
            _ =>
              @jsonutil.jsonrpc_error(
                @types.RequestId::Int(0),
                -32603,
                "Internal server error",
              )
          }
          // try_put 是非阻塞的，对于Unbounded队列总是成功
          let _ = response_queue.try_put(response) catch { _ => false }
          ()
        } else {
          // 慢速路径：为可能的I/O密集型操作spawn协程
          group.spawn_bg(fn() {
            let response = self.handle_request(message) catch {
              _ =>
                @jsonutil.jsonrpc_error(
                  @types.RequestId::Int(0),
                  -32603,
                  "Internal server error",
                )
            }
            // 把响应放入队列
            response_queue.put(response) catch {
              _ => () // 队列已关闭，忽略
            }
          })
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
    @transport.StdioTransport::new(),
  )
  @async.with_task_group(fn(group) { self.run(transport, group) }) catch {
    e => raise @types.ReadError("TaskGroup error: " + e.to_string())
  }
}

///|
pub async fn MCPServer::run_http(
  self : MCPServer,
  port? : Int = 4240,
  path? : String = "/mcp",
  group~ : @async.TaskGroup[Unit],
) -> Unit raise @types.TransportError {
  let http = @transport.HttpTransport::new(port~, endpoint_path=path)
  let http = match self.auth_config {
    Some(auth) => http.with_auth(auth)
    None => http
  }
  group.spawn_bg(async fn() { http.start() })
  let transport = @transport.AnyTransport::Http(http)
  self.run(transport, group)
}

///|
pub fn mcp_server(name~ : String, version~ : String) -> MCPServer {
  MCPServer::new(name, version)
}
