///|
fn MCPServer::tools_are_enabled(self : MCPServer) -> Bool {
  self.tools_enabled.unwrap_or(!self.registry.tools.is_empty())
}

///|
fn MCPServer::resources_are_enabled(self : MCPServer) -> Bool {
  self.resources_enabled.unwrap_or(
    !self.resource_registry.resources.is_empty() ||
    !self.resource_registry.templates.is_empty(),
  )
}

///|
fn MCPServer::prompts_are_enabled(self : MCPServer) -> Bool {
  self.prompts_enabled.unwrap_or(!self.prompt_registry.prompts.is_empty())
}

///|
fn MCPServer::supports_method(self : MCPServer, method_name : String) -> Bool {
  match method_name {
    "tools/list" | "tools/call" => self.tools_are_enabled()
    "resources/list" | "resources/templates/list" | "resources/read" =>
      self.resources_are_enabled()
    "prompts/list" | "prompts/get" => self.prompts_are_enabled()
    "completion/complete" => self.completion_registry is Some(_)
    _ => true
  }
}

///|
fn MCPServer::supported_subscription_filter(
  self : MCPServer,
  requested : SubscriptionFilter,
) -> SubscriptionFilter {
  {
    tools_list_changed: requested.tools_list_changed && self.tools_are_enabled(),
    resources_list_changed: requested.resources_list_changed &&
    self.resources_are_enabled(),
    prompts_list_changed: requested.prompts_list_changed &&
    self.prompts_are_enabled(),
    resource_subscriptions: if self.resources_are_enabled() {
      requested.resource_subscriptions.copy()
    } else {
      []
    },
  }
}

///|
/// Enable an empty tools registry, or explicitly disable tools even after registration.
/// Without an override, registering a tool enables tools automatically.
pub fn MCPServer::with_tools(
  self : MCPServer,
  enabled? : Bool = true,
) -> MCPServer {
  { ..self, tools_enabled: Some(enabled), }
}

///|
/// Enable an empty resources/templates registry, or explicitly disable its methods.
pub fn MCPServer::with_resources(
  self : MCPServer,
  enabled? : Bool = true,
) -> MCPServer {
  { ..self, resources_enabled: Some(enabled), }
}

///|
/// Enable an empty prompts registry, or explicitly disable its methods.
pub fn MCPServer::with_prompts(
  self : MCPServer,
  enabled? : Bool = true,
) -> MCPServer {
  { ..self, prompts_enabled: Some(enabled), }
}

///|
/// Return only capabilities implemented and enabled by this server.
pub fn MCPServer::capabilities(self : MCPServer) -> @types.ServerCapabilities {
  @types.ServerCapabilities::new(
    tools?=if self.tools_are_enabled() {
      Some(@types.ToolCapabilities::new(list_changed=true))
    } else {
      None
    },
    resources?=if self.resources_are_enabled() {
      Some(@types.ResourceCapabilities::new(subscribe=true, list_changed=true))
    } else {
      None
    },
    prompts?=if self.prompts_are_enabled() {
      Some(@types.PromptCapabilities::new(list_changed=true))
    } else {
      None
    },
    completions?=if self.completion_registry is Some(_) {
      Some(Map([]))
    } else {
      None
    },
  )
}
