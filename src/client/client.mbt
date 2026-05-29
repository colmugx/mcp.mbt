///|
pub struct MCPClient {
  client_name : String
  client_version : String
  mut transport : @transport.AnyTransport?
  mut server_info : @types.ServerInfo?
  mut initialized : Bool
  mut next_id : Int
  mut on_tools_changed : (() -> Unit)?
  mut on_resources_changed : (() -> Unit)?
  mut on_prompts_changed : (() -> Unit)?
}

///|
pub fn MCPClient::new(name~ : String, version~ : String) -> MCPClient {
  {
    client_name: name,
    client_version: version,
    transport: None,
    server_info: None,
    initialized: false,
    next_id: 0,
    on_tools_changed: None,
    on_resources_changed: None,
    on_prompts_changed: None,
  }
}

///|
pub fn MCPClient::next_request_id(self : MCPClient) -> Int {
  self.next_id = self.next_id + 1
  self.next_id
}

///|
async fn MCPClient::send_request(
  self : MCPClient,
  request : String,
) -> Result[String, @types.MCPError] {
  match self.transport {
    Some(t) => {
      t.send(request) catch {
        e => return Err(@types.TransportError(e))
      }
      let response = t.receive() catch {
        e => return Err(@types.TransportError(e))
      }
      match response {
        Some(msg) => Ok(msg)
        None => Err(@types.TransportError(@types.ConnectionClosed))
      }
    }
    None =>
      Err(@types.TransportError(@types.InvalidState("No transport connected")))
  }
}

///|
async fn MCPClient::send_notification(
  self : MCPClient,
  notification : String,
) -> Result[Unit, @types.MCPError] {
  match self.transport {
    Some(t) => {
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
    None =>
      Err(@types.TransportError(@types.InvalidState("No transport connected")))
  }
}

///|
pub async fn MCPClient::initialize(
  self : MCPClient,
) -> Result[Unit, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_initialize_request(
    id,
    self.client_name,
    self.client_version,
  )
  match self.send_request(request) {
    Err(e) => return Err(e)
    Ok(response) => {
      let json = @json.parse(response) catch {
        _ => return Err(@types.ParseError("Invalid JSON response"))
      }
      if json is Object(obj) {
        match obj.get("error") {
          Some(err) =>
            return Err(
              @types.InternalError("Server returned error: " + err.to_string()),
            )
          None => ()
        }
        let result = obj.get("result")
        match result {
          Some(Object(result_obj)) => {
            let server_info_json = result_obj.get("serverInfo")
            match server_info_json {
              Some(Object(info)) => {
                let name = match info.get("name") {
                  Some(String(n)) => n
                  _ => "unknown"
                }
                let version = match info.get("version") {
                  Some(String(v)) => v
                  _ => "unknown"
                }
                self.server_info = Some({
                  name,
                  title: None,
                  version,
                  description: None,
                })
              }
              _ => ()
            }
          }
          _ => ()
        }
      }
    }
  }
  let notif = build_initialized_notification()
  match self.send_notification(notif) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.initialized = true
  Ok(())
}

///|
pub async fn MCPClient::list_tools(
  self : MCPClient,
) -> Result[String, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_tools_list_request(id)
  self.send_request(request)
}

///|
pub async fn MCPClient::call_tool(
  self : MCPClient,
  name : String,
  arguments? : String = "{}",
) -> Result[String, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_tools_call_request(id, name, arguments~)
  self.send_request(request)
}

///|
pub async fn MCPClient::list_resources(
  self : MCPClient,
) -> Result[String, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_resources_list_request(id)
  self.send_request(request)
}

///|
pub async fn MCPClient::read_resource(
  self : MCPClient,
  uri : String,
) -> Result[String, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_resources_read_request(id, uri)
  self.send_request(request)
}

///|
pub async fn MCPClient::list_prompts(
  self : MCPClient,
) -> Result[String, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_prompts_list_request(id)
  self.send_request(request)
}

///|
pub async fn MCPClient::get_prompt(
  self : MCPClient,
  name : String,
  arguments? : String = "{}",
) -> Result[String, @types.MCPError] {
  let id = self.next_request_id()
  let request = build_prompts_get_request(id, name, arguments~)
  self.send_request(request)
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
pub fn MCPClient::on_tools_changed(
  self : MCPClient,
  handler : () -> Unit,
) -> Unit {
  self.on_tools_changed = Some(handler)
}

///|
pub fn MCPClient::on_resources_changed(
  self : MCPClient,
  handler : () -> Unit,
) -> Unit {
  self.on_resources_changed = Some(handler)
}

///|
pub fn MCPClient::on_prompts_changed(
  self : MCPClient,
  handler : () -> Unit,
) -> Unit {
  self.on_prompts_changed = Some(handler)
}

///|
pub fn MCPClient::set_transport(
  self : MCPClient,
  transport : @transport.AnyTransport,
) -> Unit {
  self.transport = Some(transport)
}

///|
pub fn MCPClient::close(self : MCPClient) -> Unit {
  match self.transport {
    Some(t) => {
      t.close()
      self.transport = None
    }
    None => ()
  }
  self.initialized = false
  self.server_info = None
}
