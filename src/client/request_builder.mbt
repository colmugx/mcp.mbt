///|
fn client_capabilities_to_json(
  capabilities : @types.ClientCapabilities,
) -> Json {
  capabilities.to_json()
}

///|
/// Build the `_meta` object every modern request carries in its `params`.
/// Contains the required `io.modelcontextprotocol/protocolVersion` and
/// `clientCapabilities`, plus the recommended `clientInfo`. The optional
/// `logLevel` maps to the per-request `_meta` field that replaced the removed
/// `logging/setLevel` RPC — note the Logging feature itself is Deprecated by
/// the spec (SEP-2577: new implementations should not add support), so this
/// exists for interop with servers that still honor it, and nothing in this
/// SDK reads or emits log-level-gated messages.
fn build_request_meta(
  client_name : String,
  client_version : String,
  capabilities : @types.ClientCapabilities,
  log_level? : String? = None,
) -> Json {
  let meta : Map[String, Json] = Default::default()
  meta.set(
    "io.modelcontextprotocol/protocolVersion",
    Json::string(@types.ProtocolVersion),
  )
  meta.set(
    "io.modelcontextprotocol/clientCapabilities",
    client_capabilities_to_json(capabilities),
  )
  meta.set("io.modelcontextprotocol/clientInfo", {
    "name": client_name,
    "version": client_version,
  })
  match log_level {
    Some(level) =>
      meta.set("io.modelcontextprotocol/logLevel", Json::string(level))
    None => ()
  }
  Json::object(meta)
}

///|
fn build_tools_list_request(
  id : Int,
  meta : Json,
  cursor? : String = "",
) -> String {
  let params : Map[String, Json] = Default::default()
  params.set("_meta", meta)
  if cursor != "" {
    params.set("cursor", Json::string(cursor))
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "tools/list",
    "params": Json::object(params),
  }).stringify()
}

///|
fn parse_argument_object(arguments : String) -> Json raise @types.MCPError {
  let value = @json.parse(arguments) catch {
    _ => raise @types.InvalidParams("Arguments must be valid JSON")
  }
  guard value is Object(_) else {
    raise @types.InvalidParams("Arguments must be a JSON object")
  }
  value
}

///|
fn build_tools_call_request(
  id : Int,
  name : String,
  meta : Json,
  arguments? : String = "{}",
  progress_token? : @types.ProgressToken,
) -> String raise @types.MCPError {
  let arguments_json = parse_argument_object(arguments)
  let params_map : Map[String, Json] = Default::default()
  params_map.set("name", Json::string(name))
  params_map.set("arguments", arguments_json)
  // Merge progressToken into the request _meta alongside protocol-level fields.
  match meta {
    Object(obj) => {
      let fields = obj.copy()
      match progress_token {
        Some(token) => {
          let value = token.to_json()
          ignore(@types.ProgressToken::from_json(value))
          fields.set("progressToken", value)
        }
        None => ()
      }
      params_map.set("_meta", Json::object(fields))
    }
    _ => params_map.set("_meta", meta)
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "tools/call",
    "params": Json::object(params_map),
  }).stringify()
}

///|
fn build_resources_list_request(
  id : Int,
  meta : Json,
  cursor? : String = "",
) -> String {
  let params : Map[String, Json] = Default::default()
  params.set("_meta", meta)
  if cursor != "" {
    params.set("cursor", Json::string(cursor))
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "resources/list",
    "params": Json::object(params),
  }).stringify()
}

///|
fn build_resources_read_request(id : Int, uri : String, meta : Json) -> String {
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "resources/read",
    "params": { "uri": uri, "_meta": meta },
  }).stringify()
}

///|
fn build_prompts_list_request(
  id : Int,
  meta : Json,
  cursor? : String = "",
) -> String {
  let params : Map[String, Json] = Default::default()
  params.set("_meta", meta)
  if cursor != "" {
    params.set("cursor", Json::string(cursor))
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "prompts/list",
    "params": Json::object(params),
  }).stringify()
}

///|
fn build_prompts_get_request(
  id : Int,
  name : String,
  meta : Json,
  arguments? : String = "{}",
) -> String raise @types.MCPError {
  let arguments_json = parse_argument_object(arguments)
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "prompts/get",
    "params": { "name": name, "arguments": arguments_json, "_meta": meta },
  }).stringify()
}

///|
fn build_resources_templates_list_request(
  id : Int,
  meta : Json,
  cursor? : String = "",
) -> String {
  let params : Map[String, Json] = Default::default()
  params.set("_meta", meta)
  if cursor != "" {
    params.set("cursor", Json::string(cursor))
  }
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "resources/templates/list",
    "params": Json::object(params),
  }).stringify()
}

///|
fn build_completion_reference_request(
  id : Int,
  meta : Json,
  reference : @types.CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
) -> String {
  let context = context_arguments.map(fn(arguments) {
    @types.CompletionContext::new(arguments~)
  })
  let params = @types.CompleteRequestParams::new(
    reference,
    @types.CompletionArgument::new(argument_name, argument_value),
    context?,
  ).to_json()
  guard params is Object(fields) else {
    abort("Completion params must be an object")
  }
  fields.set("_meta", meta)
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "completion/complete",
    "params": Json::object(fields),
  }).stringify()
}

///|
/// Build a `subscriptions/listen` request. Per the 2026-07-28 spec
/// (basic/patterns/subscriptions), `params.notifications` is a boolean
/// opt-in object (SubscriptionFilter), not a list of method names; each
/// field is emitted only when the filter enables it, and
/// `resourceSubscriptions` nests inside `notifications` and is omitted
/// when empty. This mirrors the server-side `parse_subscription_filter`
/// semantics: absent fields simply mean "not subscribed".
fn build_subscriptions_listen_request(
  id : Int,
  meta : Json,
  filter : ListenFilter,
) -> String {
  let notifications : Map[String, Json] = Default::default()
  if filter.tools_list_changed {
    notifications.set("toolsListChanged", Json::boolean(true))
  }
  if filter.prompts_list_changed {
    notifications.set("promptsListChanged", Json::boolean(true))
  }
  if filter.resources_list_changed {
    notifications.set("resourcesListChanged", Json::boolean(true))
  }
  if filter.resource_subscriptions.length() > 0 {
    notifications.set(
      "resourceSubscriptions",
      Json::array(filter.resource_subscriptions.map(Json::string)),
    )
  }
  let params : Map[String, Json] = Default::default()
  params.set("notifications", Json::object(notifications))
  params.set("_meta", meta)
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "subscriptions/listen",
    "params": Json::object(params),
  }).stringify()
}

///|
/// Build a `server/discover` request. Per the 2026-07-28 spec the request
/// carries no parameters beyond the standard `_meta`; it is the primary way
/// clients learn a server's supported versions, capabilities, and identity,
/// and serves as the era probe for legacy fallback.
fn build_discover_request(id : Int, meta : Json) -> String {
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "server/discover",
    "params": { "_meta": meta },
  }).stringify()
}

///|
using @transport {type HeaderSchemaValidation}

///|
fn validate_tool_header_schema(input_schema : Json) -> HeaderSchemaValidation {
  @transport.validate_tool_header_schema(input_schema)
}
