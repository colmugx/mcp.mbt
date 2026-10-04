///|
fn capability_request(method_name : String) -> String {
  Json::object({
    "jsonrpc": "2.0",
    "id": 1,
    "method": method_name,
    "params": { "_meta": valid_request_meta() },
  }).stringify()
}

///|
async test "server disabled capabilities return MethodNotFound rather than success or InvalidParams" {
  let server = MCPServer::MCPServer("test", "1")
  assert_eq(server.capabilities().to_json(), {})
  for
    method_name in [
      "tools/list", "tools/call", "resources/list", "resources/read", "resources/templates/list",
      "prompts/list", "prompts/get", "completion/complete",
    ] {
    let response = @json.parse(
      server.handle_request(capability_request(method_name)),
    )
    assert_eq(
      json_get(json_get(response, "error"), "code"),
      Json::number(-32601),
    )
  }
}

///|
async test "explicit empty registries advertise support and return empty lists" {
  let server = MCPServer::MCPServer("test", "1")
    .with_tools()
    .with_resources()
    .with_prompts()
  let caps = server.capabilities()
  assert_true(caps.tools is Some(_))
  assert_true(caps.resources is Some(cap) && cap.subscribe == Some(true))
  assert_true(caps.prompts is Some(_))
  assert_true(caps.completions is None)
  for
    (method_name, field) in [
      ("tools/list", "tools"),
      ("resources/list", "resources"),
      ("resources/templates/list", "resourceTemplates"),
      ("prompts/list", "prompts"),
    ] {
    let response = @json.parse(
      server.handle_request(capability_request(method_name)),
    )
    assert_eq(json_get(json_get(response, "result"), field), Json::array([]))
  }
  let discovery = parse_result(
    server.handle_request(capability_request("server/discover")),
  )
  assert_eq(json_get(discovery, "capabilities"), caps.to_json())
}

///|
async test "tool registration enables tools automatically and explicit disabling wins" {
  let server = MCPServer::MCPServer("test", "1").tool(
    "test",
    "test",
    { "type": "object" },
    (_context, _args) => Ok(@types.ToolResult::text("done")),
  )
  assert_true(server.capabilities().tools is Some(_))
  assert_true(server.capabilities().resources is None)
  let disabled = server.with_tools(enabled=false)
  assert_true(disabled.capabilities().tools is None)
  let response = @json.parse(
    disabled.handle_request(capability_request("tools/call")),
  )
  assert_eq(json_get(json_get(response, "error"), "code"), Json::number(-32601))
  assert_eq(disabled.registry.list_tools().length(), 1)
}

///|
test "resource templates and prompt registration enable only their own capabilities" {
  let server = MCPServer::MCPServer("test", "1")
    .resource_template(uri_template="memo://{id}", name="memo")
    .prompt("greet", "greeting", [], (_context, _arguments) => {
      Ok(@types.GetPromptResult::new([]))
    })
  assert_true(server.capabilities().tools is None)
  assert_true(server.capabilities().resources is Some(_))
  assert_true(server.capabilities().prompts is Some(_))
  assert_true(
    server.with_resources(enabled=false).capabilities().resources is None,
  )
  assert_true(server.with_prompts(enabled=false).capabilities().prompts is None)
}

///|
test "subscription acknowledgments agree only enabled notification capabilities" {
  let requested : SubscriptionFilter = {
    tools_list_changed: true,
    prompts_list_changed: true,
    resources_list_changed: true,
    resource_subscriptions: ["memo://1"],
  }
  let server = MCPServer::MCPServer("test", "1").with_tools()
  let agreed = server.supported_subscription_filter(requested)
  assert_true(agreed.tools_list_changed)
  assert_false(agreed.prompts_list_changed)
  assert_false(agreed.resources_list_changed)
  assert_true(agreed.resource_subscriptions.is_empty())
  assert_eq(requested.resource_subscriptions, ["memo://1"])
  assert_true(
    server.with_resources().supported_subscription_filter(requested).resources_list_changed,
  )
}
