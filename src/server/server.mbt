///| MCPServer - Main Server Implementation

///|
pub(all) enum ReplyHandle {
  Stdio(@aqueue.Queue[String])
  Http(@async.Queue[String])
}

///|
pub(all) struct ServerRequest {
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
/// One active `subscriptions/listen` stream. The server holds these so it can
/// route change notifications to the right client stream. Keyed by the
/// subscription id (the listen request's JSON-RPC id, stringified).
pub(all) struct ActiveSubscription {
  /// Which notification types this subscription opted into.
  filter : SubscriptionFilter
  /// Where to send notifications for this subscription.
  reply : ReplyHandle
}

///|
/// A `subscriptions/listen` notification filter (spec §subscriptions). Each
/// field is optional; omitting a field means "not subscribed to that type".
pub(all) struct SubscriptionFilter {
  mut tools_list_changed : Bool
  mut prompts_list_changed : Bool
  mut resources_list_changed : Bool
  mut resource_subscriptions : Array[String]
}

///|
/// An empty filter (subscribe to nothing) — the default when fields are absent.
pub fn SubscriptionFilter::empty() -> SubscriptionFilter {
  {
    tools_list_changed: false,
    prompts_list_changed: false,
    resources_list_changed: false,
    resource_subscriptions: [],
  }
}

///|
/// Does this filter opt into the given notification kind? A
/// `ResourceUpdated(uri)` matches only if the subscription listed that URI
/// in its `resourceSubscriptions` filter.
pub fn SubscriptionFilter::matches(
  self : SubscriptionFilter,
  kind : @types.SubscriptionNotificationKind,
) -> Bool {
  match kind {
    ToolsListChanged => self.tools_list_changed
    PromptsListChanged => self.prompts_list_changed
    ResourcesListChanged => self.resources_list_changed
    ResourceUpdated(uri~) => self.resource_subscriptions.contains(uri)
  }
}

///|
/// Inject `io.modelcontextprotocol/subscriptionId` into a notification's
/// `_meta`, so the client can demultiplex it to the originating stream.
/// `id_str` is the stringified JSON-RPC id of the listen request. If the
/// notification has no `params` or `_meta`, they are created.
fn tag_notification_with_subscription(
  notification_json : String,
  id_str : String,
) -> String {
  let json = @json.parse(notification_json) catch {
    _ => return notification_json
  }
  if json is Object(obj) {
    let params = match obj.get("params") {
      Some(Object(p)) => p
      _ => {
        let p : Map[String, Json] = Map([])
        obj.set("params", Json::object(p))
        p
      }
    }
    let meta = match params.get("_meta") {
      Some(Object(m)) => m
      _ => {
        let m : Map[String, Json] = Map([])
        params.set("_meta", Json::object(m))
        m
      }
    }
    meta.set("io.modelcontextprotocol/subscriptionId", Json::string(id_str))
    json.stringify()
  } else {
    notification_json
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
  /// Optional AEAD codec for MRTR `requestState`. When `None`, the server
  /// does not issue `input_required` results (MRTR disabled).
  request_state_codec : AesGcmStateCodec?
  /// Wall-clock source (unix seconds) for MRTR expiry. Defaults to a stub
  /// returning 0; production servers inject a real clock so `requestState`
  /// expiry is enforced. Test servers inject a fixed value.
  clock : () -> Int
  registry : ToolRegistry
  resource_registry : ResourceRegistry
  prompt_registry : PromptRegistry
  /// Active `subscriptions/listen` streams, keyed by subscription id (the
  /// listen request's JSON-RPC id, stringified).
  subscriptions : Map[String, ActiveSubscription]
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
    request_state_codec: None,
    clock: fn() { 0 },
    registry: ToolRegistry::ToolRegistry(),
    resource_registry: ResourceRegistry::ResourceRegistry(),
    prompt_registry: PromptRegistry::PromptRegistry(),
    subscriptions: {},
  }
}

///|
fn MCPServer::register_tool(
  self : MCPServer,
  name : String,
  description : String,
  input_schema : Json,
  handler : async (Json) -> Result[@tool.ToolCallOutcome, @types.MCPError],
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
  self.resource_registry.register_simple(
    uri, name, description, mime_type, handler,
  )
}

///|
fn MCPServer::register_resource_mrtr(
  self : MCPServer,
  uri : String,
  name : String,
  description : String,
  mime_type : String,
  handler : async (Json) -> Result[
    @resource.ResourceReadOutcome,
    @types.MCPError,
  ],
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
fn[T : @resource.ResourceMRTR] MCPServer::register_trait_resource_mrtr(
  self : MCPServer,
  resource : T,
) -> Unit {
  self.resource_registry.register_trait_resource_mrtr(resource)
}

///|
fn MCPServer::register_prompt(
  self : MCPServer,
  name : String,
  description : String,
  arguments : Array[@types.PromptArgument],
  handler : async (Json) -> Result[@types.GetPromptResult, @types.MCPError],
) -> Unit {
  self.prompt_registry.register_simple(name, description, arguments, handler)
}

///|
fn MCPServer::register_prompt_mrtr(
  self : MCPServer,
  name : String,
  description : String,
  arguments : Array[@types.PromptArgument],
  handler : async (Json) -> Result[@prompt.PromptGetOutcome, @types.MCPError],
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
fn[T : @prompt.PromptMRTR] MCPServer::register_trait_prompt_mrtr(
  self : MCPServer,
  prompt : T,
) -> Unit {
  self.prompt_registry.register_trait_prompt_mrtr(prompt)
}

///|
fn MCPServer::register_resource_template(
  self : MCPServer,
  uri_template : String,
  name : String,
  description : String?,
  mime_type : String?,
) -> Unit {
  self.resource_registry.register_template(
    uri_template, name, description, mime_type,
  )
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
  method_name == "server/discover" ||
  method_name == "tools/list" ||
  method_name == "resources/list" ||
  method_name == "resources/templates/list" ||
  method_name == "prompts/list"
}

///|
/// A JSON-RPC message with a `method` but no `id` is a notification; the
/// receiver MUST NOT respond to it (spec §basic). Used to route inbound
/// notifications (e.g. stdio `notifications/cancelled`) away from the
/// request path, which would otherwise reject them for the missing `id`.
fn is_notification_message(message : String) -> Bool {
  let json = @json.parse(message) catch { _ => return false }
  if json is Object(obj) {
    obj.get("id") is None && obj.get("method") is Some(String(_))
  } else {
    false
  }
}

///|
async fn MCPServer::handle_parsed_request(
  self : MCPServer,
  request : @types.JsonRpcRequest,
) -> String {
  // Reject unsupported protocol versions early on every request path.
  match check_protocol_version(request.id, request.params) {
    Some(error_response) => return error_response
    None => ()
  }
  match request.method_name {
    "server/discover" => handle_discover(self, request.id)
    "tools/list" => handle_tools_list(self, request.id)
    "tools/call" => handle_tools_call(self, request.id, request.params)
    "resources/list" => handle_resources_list(self, request.id)
    "resources/templates/list" =>
      handle_resources_templates_list(self, request.id)
    "resources/read" => handle_resources_read(self, request.id, request.params)
    "prompts/list" => handle_prompts_list(self, request.id)
    "prompts/get" => handle_prompts_get(self, request.id, request.params)
    // 2026-07-28 server: `initialize` was removed. Name the supported version
    // in the error so legacy clients get a clear signal.
    "initialize" =>
      jsonrpc_error_str(
        request.id,
        -32601,
        "Method not found: initialize — this server speaks MCP 2026-07-28; supportedVersions: [\"2026-07-28\"]",
      )
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
/// Build the `notifications/subscriptions/acknowledged` message: the first
/// message on a listen stream, carrying the subscription id (the listen
/// request's JSON-RPC id) and the agreed-upon filter subset.
fn subscriptions_acknowledged_str(
  id : @types.RequestId,
  filter : SubscriptionFilter,
) -> String {
  let acked : Map[String, Json] = Default::default()
  if filter.tools_list_changed {
    acked.set("toolsListChanged", Json::boolean(true))
  }
  if filter.prompts_list_changed {
    acked.set("promptsListChanged", Json::boolean(true))
  }
  if filter.resources_list_changed {
    acked.set("resourcesListChanged", Json::boolean(true))
  }
  if !filter.resource_subscriptions.is_empty() {
    acked.set(
      "resourceSubscriptions",
      Json::array(
        filter.resource_subscriptions.map(fn(uri) { Json::string(uri) }),
      ),
    )
  }
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/subscriptions/acknowledged"),
    "params": Json::object({
      "_meta": Json::object({
        "io.modelcontextprotocol/subscriptionId": request_id_to_json(id),
      }),
      "notifications": Json::object(acked),
    }),
  }).stringify()
}

///|
/// Parse the `notifications` filter from a `subscriptions/listen` request's
/// params. Absent fields default to false / empty.
fn parse_subscription_filter(params : Json) -> SubscriptionFilter {
  let filter = SubscriptionFilter::empty()
  if params is Object(obj) {
    match obj.get("notifications") {
      Some(Object(n)) => {
        match n.get("toolsListChanged") {
          Some(True) => filter.tools_list_changed = true
          _ => ()
        }
        match n.get("promptsListChanged") {
          Some(True) => filter.prompts_list_changed = true
          _ => ()
        }
        match n.get("resourcesListChanged") {
          Some(True) => filter.resources_list_changed = true
          _ => ()
        }
        match n.get("resourceSubscriptions") {
          Some(Array(uris)) =>
            for uri in uris {
              if uri is String(s) {
                filter.resource_subscriptions.push(s)
              }
            }
          _ => ()
        }
      }
      _ => ()
    }
  }
  filter
}

///|
/// Handle `subscriptions/listen` (spec §subscriptions). Registers the
/// subscription, sends the acknowledgment (the first message on the stream),
/// and keeps the subscription registered so later `notify_*` calls route
/// matching notifications to this stream. The stream ends when the client
/// cancels or the transport closes.
async fn MCPServer::handle_subscriptions_listen(
  self : MCPServer,
  request : @types.JsonRpcRequest,
  reply : ReplyHandle,
) -> Unit {
  let filter = parse_subscription_filter(request.params)
  let sub_id = request.id.to_json_string()
  // Register before acknowledging so notifications aren't lost.
  self.subscriptions.set(sub_id, { filter, reply, })
  // Send the acknowledgment as the first stream message.
  let ack = subscriptions_acknowledged_str(request.id, filter)
  reply.send(ack) catch {
    _ => self.subscriptions.remove(sub_id)
  }
}

///|
/// Push a change notification to every active subscription whose filter
/// matches the given kind. `notification_json` is the full JSON-RPC
/// notification string; `subscription_id` is attached to `_meta` per spec.
/// Subscriptions whose reply has failed are dropped.
async fn MCPServer::notify_subscriptions(
  self : MCPServer,
  kind : @types.SubscriptionNotificationKind,
  notification_json : String,
) -> Unit {
  // Snapshot the ids to avoid mutating the map during iteration.
  let ids : Array[String] = []
  self.subscriptions.each(fn(k, _) { ids.push(k) })
  for id in ids {
    match self.subscriptions.get(id) {
      Some(sub) =>
        if SubscriptionFilter::matches(sub.filter, kind) {
          let tagged = tag_notification_with_subscription(notification_json, id)
          sub.reply.send(tagged) catch {
            _ => self.subscriptions.remove(id)
          }
        }
      None => ()
    }
  }
}

///|
/// Public server-side notification triggers. Each routes to matching
/// `subscriptions/listen` streams.
pub async fn MCPServer::notify_tools_list_changed(self : MCPServer) -> Unit {
  let n = @types.tools_list_changed_notification().to_jsonrpc_string()
  self.notify_subscriptions(
    @types.SubscriptionNotificationKind::ToolsListChanged,
    n,
  )
}

///|
pub async fn MCPServer::notify_resources_list_changed(self : MCPServer) -> Unit {
  let n = @types.resources_list_changed_notification().to_jsonrpc_string()
  self.notify_subscriptions(
    @types.SubscriptionNotificationKind::ResourcesListChanged,
    n,
  )
}

///|
/// Announce that a specific resource's content changed. Reaches only the
/// subscriptions that listed `uri` in their `resourceSubscriptions` filter —
/// this is the 2026-07-28 replacement for the legacy `resources/subscribe`
/// per-URI push.
pub async fn MCPServer::notify_resource_updated(
  self : MCPServer,
  uri : String,
) -> Unit {
  let n = @types.resources_updated_notification(uri).to_jsonrpc_string()
  self.notify_subscriptions(
    @types.SubscriptionNotificationKind::ResourceUpdated(uri~),
    n,
  )
}

///|
pub async fn MCPServer::notify_prompts_list_changed(self : MCPServer) -> Unit {
  let n = @types.prompts_list_changed_notification().to_jsonrpc_string()
  self.notify_subscriptions(
    @types.SubscriptionNotificationKind::PromptsListChanged,
    n,
  )
}

///|
/// Gracefully close an active `subscriptions/listen` stream. Sends an empty
/// `complete` result carrying `io.modelcontextprotocol/subscriptionId` and
/// removes the subscription. The caller is responsible for any transport-level
/// stream teardown beyond removing the subscription.
pub async fn MCPServer::close_subscription(
  self : MCPServer,
  subscription_id : String,
) -> Unit {
  match self.subscriptions.get(subscription_id) {
    Some(sub) => {
      let result : Map[String, Json] = Default::default()
      result.set("resultType", Json::string("complete"))
      result.set(
        "_meta",
        Json::object({
          "io.modelcontextprotocol/subscriptionId": Json::string(
            subscription_id,
          ),
        }),
      )
      let id_json = @json.parse(subscription_id) catch { _ => Json::null() }
      let response = Json::object({
        "jsonrpc": Json::string("2.0"),
        "id": id_json,
        "result": Json::object(result),
      }).stringify()
      sub.reply.send(response) catch {
        _ => ()
      }
      self.subscriptions.remove(subscription_id)
    }
    None => ()
  }
}

///|
/// Handle inbound notifications (messages with a method but no id).
/// `notifications/cancelled` is treated specially when its `requestId` matches
/// an active subscription: it triggers graceful closure of that subscription.
/// Other notifications are swallowed as required by JSON-RPC 2.0.
async fn MCPServer::handle_inbound_notification(
  self : MCPServer,
  message : String,
) -> Unit {
  let json = @json.parse(message) catch { _ => return }
  if json is Object(obj) {
    match obj.get("method") {
      Some(String("notifications/cancelled")) => {
        let request_id_str = match obj.get("params") {
          Some(Object(params)) =>
            match params.get("requestId") {
              Some(Number(n, ..)) =>
                Some(@types.RequestId::Int(n.to_int()).to_json_string())
              Some(String(s)) => Some(@types.RequestId::Str(s).to_json_string())
              _ => None
            }
          _ => None
        }
        match request_id_str {
          Some(id) =>
            if self.subscriptions.contains(id) {
              self.close_subscription(id) catch {
                _ => ()
              }
            }
          None => ()
        }
      }
      _ => ()
    }
  }
}

///|
async fn MCPServer::handle_server_request(
  self : MCPServer,
  request : ServerRequest,
  group : @async.TaskGroup[Unit],
) -> Unit {
  // A message without an `id` is a notification (e.g. stdio
  // `notifications/cancelled`): the receiver MUST NOT respond to the
  // notification itself. Acting on cancellation (stopping in-flight work)
  // is a follow-up; here we only close matching subscriptions.
  if is_notification_message(request.message) {
    self.handle_inbound_notification(request.message) catch {
      _ => ()
    }
    return
  }
  match parse_request_message(request.message) {
    Err(response) => request.reply.send(response) catch { _ => () }
    Ok(parsed_request) => {
      // Reject unsupported protocol versions before routing. This covers the
      // stdio/HTTP common path, including subscriptions/listen.
      match check_protocol_version(parsed_request.id, parsed_request.params) {
        Some(error_response) => {
          request.reply.send(error_response) catch {
            _ => ()
          }
          return
        }
        None => ()
      }
      // subscriptions/listen is a long-lived request: it registers a
      // subscription, sends an acknowledgment, and stays open for future
      // notifications. Handle it specially (not via handle_parsed_request,
      // which returns a single response string).
      if parsed_request.method_name == "subscriptions/listen" {
        group.spawn_bg(() => {
          self.handle_subscriptions_listen(parsed_request, request.reply) catch {
            _ => ()
          }
        })
      } else if is_fast_method(parsed_request.method_name) {
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
          { message, reply: ReplyHandle::Stdio(response_queue), },
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
          { message, reply: ReplyHandle::Http(reply_queue), },
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
  // Convenience: simple tools return ToolResult and always complete.
  // Wrap into ToolCallOutcome for the registry.
  let wrapped = async fn(
    args : Json,
  ) -> Result[@tool.ToolCallOutcome, @types.MCPError] {
    match handler(args) {
      Ok(r) => Ok(@tool.ToolCallOutcome::Complete(r))
      Err(e) => Err(e)
    }
  }
  self.register_tool(name, description, input_schema, wrapped)
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
/// Register a resource template for `resources/templates/list`. Templates are
/// URI patterns the server can read; this call only advertises the template.
pub fn MCPServer::resource_template(
  self : MCPServer,
  uri_template~ : String,
  name~ : String,
  description? : String = "",
  mime_type? : String = "",
) -> MCPServer {
  let description = if description == "" { None } else { Some(description) }
  let mime_type = if mime_type == "" { None } else { Some(mime_type) }
  self.register_resource_template(uri_template, name, description, mime_type)
  self
}

///|
/// MRTR-aware resource registration. The handler receives the full read params
/// and may return `InputRequired` to ask the client for input before
/// completing.
pub fn MCPServer::resource_mrtr(
  self : MCPServer,
  uri : String,
  name : String,
  description : String,
  mime_type : String,
  handler : async (Json) -> Result[
    @resource.ResourceReadOutcome,
    @types.MCPError,
  ],
) -> MCPServer {
  self.register_resource_mrtr(uri, name, description, mime_type, handler)
  self
}

///|
pub fn[T : @resource.ResourceMRTR] MCPServer::with_resource_mrtr(
  self : MCPServer,
  resource : T,
) -> MCPServer {
  self.register_trait_resource_mrtr(resource)
  self
}

///|
/// MRTR-aware prompt registration. The handler receives the full get params
/// and may return `InputRequired` to ask the client for input before
/// completing.
pub fn MCPServer::prompt_mrtr(
  self : MCPServer,
  name : String,
  description : String,
  arguments : Array[@types.PromptArgument],
  handler : async (Json) -> Result[@prompt.PromptGetOutcome, @types.MCPError],
) -> MCPServer {
  self.register_prompt_mrtr(name, description, arguments, handler)
  self
}

///|
pub fn[T : @prompt.PromptMRTR] MCPServer::with_prompt_mrtr(
  self : MCPServer,
  prompt : T,
) -> MCPServer {
  self.register_trait_prompt_mrtr(prompt)
  self
}

///|
pub fn MCPServer::with_title(self : MCPServer, title : String) -> MCPServer {
  { ..self, title: Some(title), }
}

///|
pub fn MCPServer::with_description(
  self : MCPServer,
  description : String,
) -> MCPServer {
  { ..self, description: Some(description), }
}

///|
pub fn MCPServer::with_instructions(
  self : MCPServer,
  instructions : String,
) -> MCPServer {
  { ..self, instructions: Some(instructions), }
}

///|
pub fn MCPServer::with_auth(
  self : MCPServer,
  auth : @transport.AuthConfig,
) -> MCPServer {
  { ..self, auth_config: Some(auth), }
}

///|
/// Enable MRTR (Multi Round-Trip Requests) by supplying a `requestState`
/// codec. When set, handlers may return `input_required` results and verify
/// `requestState` on retry. Without a codec, MRTR is disabled.
pub fn MCPServer::with_request_state_codec(
  self : MCPServer,
  codec : AesGcmStateCodec,
) -> MCPServer {
  { ..self, request_state_codec: Some(codec), }
}

///|
/// Inject a wall-clock source (unix seconds) for MRTR `requestState` expiry.
/// Production servers should pass a real clock; the default returns 0, which
/// disables expiry enforcement (blobs never expire).
pub fn MCPServer::with_clock(self : MCPServer, clock : () -> Int) -> MCPServer {
  { ..self, clock, }
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
