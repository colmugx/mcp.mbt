///|
fn client_capabilities_to_json(
  capabilities : @types.ClientCapabilities,
) -> Json {
  let caps_map : Map[String, Json] = Default::default()
  match capabilities.roots {
    Some(roots_cap) =>
      caps_map.set("roots", { "listChanged": roots_cap.list_changed })
    None => ()
  }
  match capabilities.sampling {
    Some(_) => caps_map.set("sampling", {})
    None => ()
  }
  match capabilities.elicitation {
    Some(_) => caps_map.set("elicitation", { "form": {} })
    None => ()
  }
  match capabilities.extensions {
    Some(extensions) => {
      let ext_map : Map[String, Json] = Default::default()
      extensions.each(fn(k, v) { ext_map.set(k, v) })
      caps_map.set("extensions", Json::object(ext_map))
    }
    None => ()
  }
  Json::object(caps_map)
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
fn build_tools_call_request(
  id : Int,
  name : String,
  meta : Json,
  arguments? : String = "{}",
  progress_token? : String = "",
) -> String {
  let arguments_json = @json.parse(arguments) catch { _ => Json::object({}) }
  let params_map : Map[String, Json] = Default::default()
  params_map.set("name", Json::string(name))
  params_map.set("arguments", arguments_json)
  // Merge progressToken into the request _meta alongside protocol-level fields.
  match meta {
    Object(obj) => {
      if progress_token != "" {
        obj.set("progressToken", Json::string(progress_token))
      }
      params_map.set("_meta", meta)
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
) -> String {
  let arguments_json = @json.parse(arguments) catch { _ => Json::object({}) }
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
fn build_completion_complete_request(
  id : Int,
  meta : Json,
  ref_type~ : String,
  ref_name~ : String,
  argument_name~ : String,
  argument_value~ : String,
) -> String {
  Json::object({
    "jsonrpc": "2.0",
    "id": id,
    "method": "completion/complete",
    "params": {
      "ref": { "type": ref_type, "name": ref_name },
      "argument": { "name": argument_name, "value": argument_value },
      "_meta": meta,
    },
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
/// Result of validating one tool's `x-mcp-header` mirror schema.
priv enum HeaderSchemaValidation {
  Valid(Array[(Array[String], String)])
  Invalid(String)
}

///|
/// Validate a tool's `inputSchema` for `x-mcp-header` mirror annotations.
/// Returns the list of `(property_path, header_name)` entries when valid, or
/// an error message describing the first violation. Per the 2026-07-28
/// streamable HTTP spec:
///
/// * header names must be non-empty HTTP `tchar`s (RFC 9110 §5.1);
/// * names are case-insensitively unique within the tool;
/// * only `integer`, `string`, and `boolean` typed properties may carry the
///   annotation (not `number`);
/// * the annotation may only appear on properties statically reachable through
///   `properties` chains; any occurrence under `items`/`oneOf`/`anyOf`/`allOf`/
///   `if`/`then`/`else`/`$ref` invalidates the whole tool.
fn validate_tool_header_schema(input_schema : Json) -> HeaderSchemaValidation {
  validate_header_schema_node(input_schema, path=[], in_properties=false)
}

///|
fn validate_header_schema_node(
  schema : Json,
  path~ : Array[String],
  in_properties~ : Bool,
) -> HeaderSchemaValidation {
  match schema {
    Object(obj) => {
      // If we are in a property context and the property itself carries the
      // annotation, validate it before descending. The validated annotation
      // becomes this node's own entry in the collected result.
      let own_entries : Array[(Array[String], String)] = []
      if in_properties {
        match obj.get("x-mcp-header") {
          Some(String(header_name)) => {
            if header_name.length() == 0 {
              return Invalid("x-mcp-header value must be non-empty")
            }
            if !is_http_token(header_name) {
              return Invalid(
                "x-mcp-header contains invalid token characters: " + header_name,
              )
            }
            match property_type_is_primitive(obj) {
              false =>
                return Invalid(
                  "x-mcp-header can only annotate integer/string/boolean properties: " +
                  path.join("."),
                )
              true => ()
            }
            own_entries.push((path, header_name))
          }
          Some(_) =>
            return Invalid(
              "x-mcp-header value must be a string: " + path.join("."),
            )
          None => ()
        }
      } else if obj.contains("x-mcp-header") {
        // Annotation outside a property (root, items, combiners, etc.).
        return Invalid(
          "x-mcp-header must appear on a property: " + path.join("."),
        )
      }

      // Collect validated annotations and detect disallowed nesting.
      let collected : Array[(Array[String], String)] = []
      let disallowed = [
        "items", "oneOf", "anyOf", "allOf", "if", "then", "else", "$ref",
      ]
      for key, value in obj {
        if key == "properties" {
          match value {
            Object(props) =>
              for prop_name, prop_schema in props {
                let child_path = path.copy()
                child_path.push(prop_name)
                match
                  validate_header_schema_node(
                    prop_schema,
                    path=child_path,
                    in_properties=true,
                  ) {
                  Valid(entries) => collected.append(entries)
                  Invalid(msg) => return Invalid(msg)
                }
              }
            _ => ()
          }
        } else if disallowed.contains(key) {
          match validate_header_schema_node(value, path~, in_properties=false) {
            Valid(entries) =>
              if entries.length() > 0 {
                return Invalid(
                  "x-mcp-header cannot appear under '" +
                  key +
                  "' (must be via properties): " +
                  entries[0].0.join("."),
                )
              }
            Invalid(msg) => return Invalid(msg)
          }
        } else if key != "x-mcp-header" {
          // Other keys are allowed, but any annotation nested inside them is
          // not reachable through a pure `properties` chain.
          match validate_header_schema_node(value, path~, in_properties=false) {
            Valid(entries) =>
              if entries.length() > 0 {
                return Invalid(
                  "x-mcp-header must be reachable through properties: " +
                  entries[0].0.join("."),
                )
              }
            Invalid(msg) => return Invalid(msg)
          }
        }
      }

      // Enforce case-insensitive uniqueness among annotations found in this
      // tool's schema. Own annotation (if any) participates too.
      own_entries.append(collected)
      let seen : Map[String, Unit] = Default::default()
      for entry in own_entries {
        let lower = entry.1.to_lower()
        if seen.contains(lower) {
          return Invalid(
            "duplicate x-mcp-header (case-insensitive): " + entry.1,
          )
        }
        seen.set(lower, ())
      }
      Valid(own_entries)
    }
    Array(arr) => {
      let collected : Array[(Array[String], String)] = []
      for item in arr {
        match validate_header_schema_node(item, path~, in_properties=false) {
          Valid(entries) =>
            if entries.length() > 0 {
              return Invalid(
                "x-mcp-header cannot appear inside an array schema at path: " +
                path.join("."),
              )
            }
          Invalid(msg) => return Invalid(msg)
        }
      }
      Valid(collected)
    }
    _ => Valid([])
  }
}

///|
fn property_type_is_primitive(obj : Map[String, Json]) -> Bool {
  match obj.get("type") {
    Some(String("integer")) => true
    Some(String("string")) => true
    Some(String("boolean")) => true
    _ => false
  }
}

///|
/// Check whether every character is an HTTP `tchar` per RFC 9110 §5.1.
fn is_http_token(s : String) -> Bool {
  let mut ok = true
  for c in s {
    if !is_http_tchar(c) {
      ok = false
      break
    }
  }
  ok
}

///|
fn is_http_tchar(c : Char) -> Bool {
  if c >= 'A' && c <= 'Z' {
    return true
  }
  if c >= 'a' && c <= 'z' {
    return true
  }
  if c >= '0' && c <= '9' {
    return true
  }
  let token_specials = "!#$%&'*+-.^_`|~"
  for s in token_specials {
    if c == s {
      return true
    }
  }
  false
}
