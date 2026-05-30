///|
pub(all) struct RequestIdCounter {
  mut next_id : Int
}

///|
pub fn RequestIdCounter::new() -> RequestIdCounter {
  { next_id: 0 }
}

///|
pub fn RequestIdCounter::next(self : RequestIdCounter) -> Int {
  self.next_id = self.next_id + 1
  self.next_id
}

///|
pub struct MCPClient {
  client_name : String
  client_version : String
  transport : @transport.AnyTransport
  id_counter : RequestIdCounter
}

///|
pub fn MCPClient::new(
  name~ : String,
  version~ : String,
  transport~ : @transport.AnyTransport,
) -> MCPClient {
  {
    client_name: name,
    client_version: version,
    transport,
    id_counter: RequestIdCounter::new(),
  }
}

///|
pub fn MCPClient::next_request_id(self : MCPClient) -> Int {
  self.id_counter.next()
}

///|
async fn MCPClient::send_request(
  self : MCPClient,
  request : String,
) -> Result[String, @types.MCPError] {
  let t = self.transport
  t.send(request) catch {
    e => return Err(@types.TransportError(e))
  }
  let response = t.receive() catch { e => return Err(@types.TransportError(e)) }
  match response {
    Some(msg) => Ok(msg)
    None => Err(@types.TransportError(@types.ConnectionClosed))
  }
}

///|
async fn MCPClient::send_notification(
  self : MCPClient,
  notification : String,
) -> Result[Unit, @types.MCPError] {
  let t = self.transport
  let notif = @json.parse(notification) catch {
    _ => return Err(@types.ParseError("Invalid notification JSON"))
  }
  match notif {
    Object(obj) => {
      let method_name = match obj.get("method") {
        Some(String(m)) => m
        _ => return Err(@types.InvalidRequest("Missing method field"))
      }
      let params = obj.get("params")
      let notification_obj : @types.Notification = { method_name, params }
      t.send_notification(notification_obj) catch {
        e => return Err(@types.TransportError(e))
      }
      Ok(())
    }
    _ => Err(@types.InvalidRequest("Notification must be a JSON object"))
  }
}

///|
pub async fn MCPClient::initialize(
  self : MCPClient,
) -> Result[@types.ServerInfo, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_initialize_request(
    id,
    self.client_name,
    self.client_version,
  )
  let response_str = match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  let result_json = match parse_jsonrpc_response(response_str) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  let server_info = match result_json {
    Object(result_obj) =>
      match result_obj.get("serverInfo") {
        Some(Object(info)) => {
          let name = match info.get("name") {
            Some(String(n)) => n
            _ => "unknown"
          }
          let version = match info.get("version") {
            Some(String(v)) => v
            _ => "unknown"
          }
          ({ name, title: None, version, description: None } : @types.ServerInfo)
        }
        _ =>
          (
            {
              name: "unknown",
              title: None,
              version: "unknown",
              description: None,
            } : @types.ServerInfo)
      }
    _ =>
      (
        { name: "unknown", title: None, version: "unknown", description: None } :
        @types.ServerInfo)
  }
  let notif = build_initialized_notification()
  match self.send_notification(notif) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok(server_info)
}

///|
pub async fn MCPClient::list_tools(
  self : MCPClient,
) -> Result[ListToolsResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_tools_list_request(id)
  match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_tools_list(result_json)
      }
  }
}

///|
pub async fn MCPClient::call_tool(
  self : MCPClient,
  name : String,
  arguments? : String = "{}",
) -> Result[CallToolResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_tools_call_request(id, name, arguments~)
  match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_call_tool(result_json)
      }
  }
}

///|
pub async fn MCPClient::list_resources(
  self : MCPClient,
) -> Result[ListResourcesResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_resources_list_request(id)
  match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_list_resources(result_json)
      }
  }
}

///|
pub async fn MCPClient::read_resource(
  self : MCPClient,
  uri : String,
) -> Result[ReadResourceResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_resources_read_request(id, uri)
  match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_read_resource(result_json)
      }
  }
}

///|
pub async fn MCPClient::list_prompts(
  self : MCPClient,
) -> Result[ListPromptsResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_prompts_list_request(id)
  match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_list_prompts(result_json)
      }
  }
}

///|
pub async fn MCPClient::get_prompt(
  self : MCPClient,
  name : String,
  arguments? : String = "{}",
) -> Result[@types.GetPromptResult, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_prompts_get_request(id, name, arguments~)
  match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(response_str) =>
      match parse_jsonrpc_response(response_str) {
        Err(e) => return Err(e)
        Ok(result_json) => parse_get_prompt(result_json)
      }
  }
}

///|
pub async fn MCPClient::ping(self : MCPClient) -> Result[Unit, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_ping_request(id)
  match self.send_request(request) {
    Err(e) => Err(e)
    Ok(_) => Ok(())
  }
}

///|
pub async fn MCPClient::set_log_level(
  self : MCPClient,
  level : String,
) -> Result[Unit, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_set_log_level_request(id, level)
  match self.send_request(request) {
    Err(e) => Err(e)
    Ok(_) => Ok(())
  }
}

///|
pub fn MCPClient::close(self : MCPClient) -> Unit {
  self.transport.close()
}

///|
fn parse_jsonrpc_response(
  response_str : String,
) -> Result[Json, @types.MCPError] {
  let json = @json.parse(response_str) catch {
    _ => return Err(@types.ParseError("Invalid JSON response"))
  }
  match json {
    Object(obj) => {
      match obj.get("error") {
        Some(Object(err_obj)) => {
          let message = match err_obj.get("message") {
            Some(String(m)) => m
            _ => "Unknown error"
          }
          return Err(@types.InternalError("Server error: " + message))
        }
        _ => ()
      }
      match obj.get("result") {
        Some(result_json) => Ok(result_json)
        None => Err(@types.InvalidRequest("Response missing 'result' field"))
      }
    }
    _ => Err(@types.ParseError("Response must be a JSON object"))
  }
}

///|
fn parse_tool_def(json : Json) -> @types.ToolDefinition? {
  match json {
    Object(obj) => {
      let name = match obj.get("name") {
        Some(String(n)) => n
        _ => return None
      }
      let description = match obj.get("description") {
        Some(String(d)) => d
        _ => ""
      }
      let input_schema = obj.get("inputSchema").unwrap_or(Json::null())
      Some({
        name,
        description,
        input_schema,
        cached_schema_json: "",
        icon: None,
      })
    }
    _ => None
  }
}

///|
fn parse_tools_list(
  result_json : Json,
) -> Result[ListToolsResult, @types.MCPError] {
  match result_json {
    Object(obj) =>
      match obj.get("tools") {
        Some(Array(tools_json)) =>
          Ok({ tools: tools_json.filter_map(parse_tool_def) })
        _ => Err(@types.InvalidRequest("Missing 'tools' array in result"))
      }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_call_tool(
  result_json : Json,
) -> Result[CallToolResult, @types.MCPError] {
  match result_json {
    Object(obj) => {
      let content_items = match obj.get("content") {
        Some(Array(items)) => items.filter_map(parse_content_item)
        _ => []
      }
      let is_error = match obj.get("isError") {
        Some(True) => true
        _ => false
      }
      Ok({ content: content_items, is_error })
    }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_content_item(json : Json) -> @types.ContentItem? {
  match json {
    Object(obj) => {
      let type_ = match obj.get("type") {
        Some(String(t)) => t
        _ => return None
      }
      match type_ {
        "text" =>
          match obj.get("text") {
            Some(String(t)) => Some(@types.ContentItem::Text(t))
            _ => None
          }
        "image" =>
          match obj.get("data") {
            Some(String(d)) => {
              let mime_type = match obj.get("mimeType") {
                Some(String(m)) => m
                _ => "image/png"
              }
              Some(@types.ContentItem::Image(d, mime_type~))
            }
            _ => None
          }
        "resource_link" =>
          match obj.get("uri") {
            Some(String(u)) => Some(@types.ContentItem::ResourceLink(u))
            _ => None
          }
        "resource" =>
          match obj.get("resource") {
            Some(Object(res_obj)) =>
              match res_obj.get("uri") {
                Some(String(u)) =>
                  match res_obj.get("text") {
                    Some(String(t)) => {
                      let mime_type = match res_obj.get("mimeType") {
                        Some(String(m)) => Some(m)
                        _ => None
                      }
                      Some(
                        @types.ContentItem::EmbeddedResource(
                          @types.EmbeddedResourceContent::Text(
                            t,
                            uri=u,
                            mime_type~,
                          ),
                        ),
                      )
                    }
                    _ => None
                  }
                _ => None
              }
            _ => None
          }
        _ => None
      }
    }
    _ => None
  }
}

///|
fn parse_resource_def(json : Json) -> @resource.ResourceDefinition? {
  match json {
    Object(obj) =>
      match obj.get("uri") {
        Some(String(u)) =>
          match obj.get("name") {
            Some(String(n)) => {
              let description = match obj.get("description") {
                Some(String(d)) => Some(d)
                _ => None
              }
              let mime_type = match obj.get("mimeType") {
                Some(String(m)) => Some(m)
                _ => None
              }
              Some({ uri: u, name: n, description, mime_type })
            }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_list_resources(
  result_json : Json,
) -> Result[ListResourcesResult, @types.MCPError] {
  match result_json {
    Object(obj) =>
      match obj.get("resources") {
        Some(Array(resources_json)) =>
          Ok({ resources: resources_json.filter_map(parse_resource_def) })
        _ => Err(@types.InvalidRequest("Missing 'resources' array in result"))
      }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_resource_content(json : Json) -> @resource.ResourceReadResult? {
  match json {
    Object(obj) =>
      match obj.get("uri") {
        Some(String(u)) => {
          let content = match obj.get("text") {
            Some(String(t)) => @resource.ResourceContent::Text(t)
            None =>
              match obj.get("blob") {
                Some(String(b)) => {
                  let mime_type = match obj.get("mimeType") {
                    Some(String(m)) => m
                    _ => "application/octet-stream"
                  }
                  @resource.ResourceContent::Blob(b, mime_type~)
                }
                _ => return None
              }
            _ => return None
          }
          Some({ uri: u, content })
        }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_read_resource(
  result_json : Json,
) -> Result[ReadResourceResult, @types.MCPError] {
  match result_json {
    Object(obj) =>
      match obj.get("contents") {
        Some(Array(contents_json)) =>
          Ok({ contents: contents_json.filter_map(parse_resource_content) })
        _ => Err(@types.InvalidRequest("Missing 'contents' array in result"))
      }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_prompt_arg(json : Json) -> @types.PromptArgument? {
  match json {
    Object(obj) =>
      match obj.get("name") {
        Some(String(n)) => {
          let description = match obj.get("description") {
            Some(String(d)) => Some(d)
            _ => None
          }
          let required = match obj.get("required") {
            Some(True) => Some(true)
            Some(False) => Some(false)
            _ => None
          }
          Some({ name: n, description, required })
        }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_prompt_def(json : Json) -> @prompt.PromptDefinition? {
  match json {
    Object(obj) =>
      match obj.get("name") {
        Some(String(n)) => {
          let description = match obj.get("description") {
            Some(String(d)) => Some(d)
            _ => None
          }
          let arguments = match obj.get("arguments") {
            Some(Array(args_json)) =>
              Some(args_json.filter_map(parse_prompt_arg))
            _ => None
          }
          Some({ name: n, description, arguments })
        }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_list_prompts(
  result_json : Json,
) -> Result[ListPromptsResult, @types.MCPError] {
  match result_json {
    Object(obj) =>
      match obj.get("prompts") {
        Some(Array(prompts_json)) =>
          Ok({ prompts: prompts_json.filter_map(parse_prompt_def) })
        _ => Err(@types.InvalidRequest("Missing 'prompts' array in result"))
      }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}

///|
fn parse_prompt_message(json : Json) -> @types.PromptMessage? {
  match json {
    Object(obj) =>
      match obj.get("role") {
        Some(String(role)) =>
          match obj.get("content") {
            Some(content_json) =>
              match parse_content_item(content_json) {
                Some(item) => Some({ role, content: item })
                None => None
              }
            None => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_get_prompt(
  result_json : Json,
) -> Result[@types.GetPromptResult, @types.MCPError] {
  match result_json {
    Object(obj) => {
      let description = match obj.get("description") {
        Some(String(d)) => Some(d)
        _ => None
      }
      match obj.get("messages") {
        Some(Array(msgs_json)) =>
          Ok({
            description,
            messages: msgs_json.filter_map(parse_prompt_message),
          })
        _ => Err(@types.InvalidRequest("Missing 'messages' array in result"))
      }
    }
    _ => Err(@types.ParseError("Result must be a JSON object"))
  }
}
