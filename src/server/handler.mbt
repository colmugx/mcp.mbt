///| MCP Server Request Handlers

///|
fn request_id_to_json(id : @types.RequestId) -> Json {
  match id {
    Int(n) => Json::number(n.to_double())
    Str(s) => Json::string(s)
  }
}

///|
fn jsonrpc_success_str(id : @types.RequestId, result : Json) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": request_id_to_json(id),
    "result": result,
  }).stringify()
}

///|
fn jsonrpc_error_str(
  id : @types.RequestId,
  code : Int,
  message : String,
) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": request_id_to_json(id),
    "error": Json::object({
      "code": Json::number(code.to_double()),
      "message": Json::string(message),
    }),
  }).stringify()
}

///|
fn extract_json_string(json : Json, field : String) -> String? {
  if json is Object(obj) {
    match obj.get(field) {
      Some(String(s)) => Some(s)
      _ => None
    }
  } else {
    None
  }
}

///|
fn handle_ping(id : @types.RequestId) -> String {
  jsonrpc_success_str(id, Json::object({}))
}

///|
fn handle_initialize(server : MCPServer, id : @types.RequestId) -> String {
  let capabilities = Json::object({
    "tools": Json::object({ "listChanged": Json::boolean(true) }),
    "resources": Json::object({
      "subscribe": Json::boolean(true),
      "listChanged": Json::boolean(true),
    }),
    "prompts": Json::object({ "listChanged": Json::boolean(true) }),
    "logging": Json::object({}),
  })
  let info_map : Map[String, Json] = {}
  info_map.set("name", Json::string(server.name))
  info_map.set("version", Json::string(server.version))
  match server.title {
    Some(t) => info_map.set("title", Json::string(t))
    None => ()
  }
  match server.description {
    Some(d) => info_map.set("description", Json::string(d))
    None => ()
  }
  let server_info = Json::object(info_map)
  let result_map : Map[String, Json] = {}
  result_map.set("protocolVersion", Json::string("2025-11-25"))
  result_map.set("capabilities", capabilities)
  result_map.set("serverInfo", server_info)
  match server.instructions {
    Some(instr) => result_map.set("instructions", Json::string(instr))
    None => ()
  }
  jsonrpc_success_str(id, Json::object(result_map))
}

///|
fn handle_tools_list(server : MCPServer, id : @types.RequestId) -> String {
  let tools = server.registry.list_tools()
  let tool_jsons = tools.map(fn(tool) {
    Json::object({
      "name": Json::string(tool.name),
      "description": Json::string(tool.description),
      "inputSchema": tool.input_schema,
    })
  })
  jsonrpc_success_str(id, Json::object({ "tools": Json::array(tool_jsons) }))
}

///|
async fn handle_tools_call(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let tool_name = extract_json_string(params, "name")
  match tool_name {
    None => jsonrpc_error_str(id, -32602, "Missing 'name' parameter")
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
              @types.Text(text) =>
                Json::object({
                  "type": Json::string("text"),
                  "text": Json::string(text),
                })
              @types.Image(data, mime_type~) =>
                Json::object({
                  "type": Json::string("image"),
                  "data": Json::string(data),
                  "mimeType": Json::string(mime_type),
                })
              @types.ResourceLink(uri) =>
                Json::object({
                  "type": Json::string("resource_link"),
                  "uri": Json::string(uri),
                })
              @types.EmbeddedResource(content) =>
                match content {
                  @types.Text(text, uri~, mime_type~) => {
                    let map : Map[String, Json] = {}
                    map.set("type", Json::string("resource"))
                    map.set("uri", Json::string(uri))
                    map.set("text", Json::string(text))
                    match mime_type {
                      Some(mt) => map.set("mimeType", Json::string(mt))
                      None => ()
                    }
                    Json::object(map)
                  }
                  @types.Blob(data, uri~, mime_type~) =>
                    Json::object({
                      "type": Json::string("resource"),
                      "uri": Json::string(uri),
                      "blob": Json::string(data),
                      "mimeType": Json::string(mime_type),
                    })
                }
            }
          })
          let result = Json::object({
            "content": Json::array(content_items),
            "isError": Json::boolean(tool_result.is_error),
          })
          jsonrpc_success_str(id, result)
        }
        Err(e) => jsonrpc_error_str(id, e.to_error_code(), e.message())
      }
    }
  }
}

///|
fn handle_resources_list(server : MCPServer, id : @types.RequestId) -> String {
  let resources = server.resource_registry.list_resources()
  let resource_jsons = resources.map(fn(resource) {
    let map : Map[String, Json] = {}
    map.set("uri", Json::string(resource.uri))
    map.set("name", Json::string(resource.name))
    match resource.description {
      Some(desc) => map.set("description", Json::string(desc))
      None => ()
    }
    match resource.mime_type {
      Some(mt) => map.set("mimeType", Json::string(mt))
      None => ()
    }
    Json::object(map)
  })
  jsonrpc_success_str(
    id,
    Json::object({ "resources": Json::array(resource_jsons) }),
  )
}

///|
async fn handle_resources_read(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let uri = extract_json_string(params, "uri")
  match uri {
    None => jsonrpc_error_str(id, -32602, "Missing 'uri' parameter")
    Some(uri_str) =>
      match server.resource_registry.read_resource(uri_str) {
        Ok(read_result) => {
          let content_json = match read_result.content {
            @resource.Text(text) =>
              Json::object({
                "uri": Json::string(read_result.uri),
                "text": Json::string(text),
              })
            @resource.Blob(data, mime_type~) =>
              Json::object({
                "uri": Json::string(read_result.uri),
                "blob": Json::string(data.to_string()),
                "mimeType": Json::string(mime_type),
              })
          }
          jsonrpc_success_str(
            id,
            Json::object({ "contents": Json::array([content_json]) }),
          )
        }
        Err(e) => jsonrpc_error_str(id, e.to_error_code(), e.message())
      }
  }
}

///|
fn handle_resources_subscribe(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let uri = extract_json_string(params, "uri")
  match uri {
    None => jsonrpc_error_str(id, -32602, "Missing 'uri' parameter")
    Some(uri_str) =>
      match server.resource_registry.subscribe(uri_str) {
        Ok(_) => jsonrpc_success_str(id, Json::object({}))
        Err(e) => jsonrpc_error_str(id, e.to_error_code(), e.message())
      }
  }
}

///|
fn handle_resources_unsubscribe(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let uri = extract_json_string(params, "uri")
  match uri {
    None => jsonrpc_error_str(id, -32602, "Missing 'uri' parameter")
    Some(uri_str) =>
      match server.resource_registry.unsubscribe(uri_str) {
        Ok(_) => jsonrpc_success_str(id, Json::object({}))
        Err(e) => jsonrpc_error_str(id, e.to_error_code(), e.message())
      }
  }
}

///|
fn handle_prompts_list(server : MCPServer, id : @types.RequestId) -> String {
  let prompts = server.prompt_registry.list_prompts()
  let prompt_jsons = prompts.map(fn(prompt) {
    let map : Map[String, Json] = {}
    map.set("name", Json::string(prompt.name))
    match prompt.description {
      Some(desc) => map.set("description", Json::string(desc))
      None => ()
    }
    match prompt.arguments {
      Some(args) => {
        let arg_jsons = args.map(fn(arg) {
          let arg_map : Map[String, Json] = {}
          arg_map.set("name", Json::string(arg.name))
          match arg.description {
            Some(d) => arg_map.set("description", Json::string(d))
            None => ()
          }
          match arg.required {
            Some(true) => arg_map.set("required", Json::boolean(true))
            _ => ()
          }
          Json::object(arg_map)
        })
        map.set("arguments", Json::array(arg_jsons))
      }
      None => ()
    }
    Json::object(map)
  })
  jsonrpc_success_str(
    id,
    Json::object({ "prompts": Json::array(prompt_jsons) }),
  )
}

///|
async fn handle_prompts_get(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let prompt_name = extract_json_string(params, "name")
  match prompt_name {
    None => jsonrpc_error_str(id, -32602, "Missing 'name' parameter")
    Some(name) =>
      match server.prompt_registry.get_prompt(name, params) {
        Ok(prompt_result) => {
          let messages_json = prompt_result.messages.map(fn(msg) {
            let content = match msg.content {
              @types.Text(text) =>
                Json::object({
                  "type": Json::string("text"),
                  "text": Json::string(text),
                })
              _ => Json::null()
            }
            Json::object({ "role": Json::string(msg.role), "content": content })
          })
          let result_map : Map[String, Json] = {}
          match prompt_result.description {
            Some(d) => result_map.set("description", Json::string(d))
            None => ()
          }
          result_map.set("messages", Json::array(messages_json))
          jsonrpc_success_str(id, Json::object(result_map))
        }
        Err(e) => jsonrpc_error_str(id, e.to_error_code(), e.message())
      }
  }
}

///|
fn handle_set_level(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let level = extract_json_string(params, "level")
  match level {
    None => jsonrpc_error_str(id, -32602, "Missing 'level' parameter")
    Some(lvl) => {
      server.log_level = Some(lvl)
      jsonrpc_success_str(id, Json::object({}))
    }
  }
}
