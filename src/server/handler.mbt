///| MCP Server Request Handlers

///|
fn handle_ping(id : @types.RequestId) -> String {
  @jsonutil.jsonrpc_success(id, @jsonutil.json_object([]))
}

///|
fn handle_initialize(server : MCPServer, id : @types.RequestId) -> String {
  let tools_cap = @jsonutil.json_object([
    ("listChanged", @jsonutil.json_bool(true)),
  ])
  let resources_cap = @jsonutil.json_object([
    ("subscribe", @jsonutil.json_bool(true)),
    ("listChanged", @jsonutil.json_bool(true)),
  ])
  let prompts_cap = @jsonutil.json_object([
    ("listChanged", @jsonutil.json_bool(true)),
  ])
  let logging_cap = @jsonutil.json_object([])
  let capabilities = @jsonutil.json_object([
    ("tools", tools_cap),
    ("resources", resources_cap),
    ("prompts", prompts_cap),
    ("logging", logging_cap),
  ])
  let info_pairs : Array[(String, String)] = [
    ("name", @jsonutil.json_string(server.name)),
    ("version", @jsonutil.json_string(server.version)),
  ]
  match server.title {
    Some(t) => info_pairs.push(("title", @jsonutil.json_string(t)))
    None => ()
  }
  match server.description {
    Some(d) => info_pairs.push(("description", @jsonutil.json_string(d)))
    None => ()
  }
  let server_info = @jsonutil.json_object(info_pairs)
  let result_pairs : Array[(String, String)] = [
    ("protocolVersion", @jsonutil.json_string("2025-11-25")),
    ("capabilities", capabilities),
    ("serverInfo", server_info),
  ]
  match server.instructions {
    Some(instr) =>
      result_pairs.push(("instructions", @jsonutil.json_string(instr)))
    None => ()
  }
  let result = @jsonutil.json_object(result_pairs)
  @jsonutil.jsonrpc_success(id, result)
}

///|
fn handle_tools_list(server : MCPServer, id : @types.RequestId) -> String {
  let tools = server.registry.list_tools()
  let tool_jsons = tools.map(fn(tool) {
    @jsonutil.json_object([
      ("name", @jsonutil.json_string(tool.name)),
      ("description", @jsonutil.json_string(tool.description)),
      ("inputSchema", tool.cached_schema_json),
    ])
  })
  let result = @jsonutil.json_object([
    ("tools", @jsonutil.json_array(tool_jsons)),
  ])
  @jsonutil.jsonrpc_success(id, result)
}

///|
async fn handle_tools_call(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let tool_name = @jsonutil.extract_string_from_json(params, "name")
  match tool_name {
    None => @jsonutil.jsonrpc_error(id, -32602, "Missing 'name' parameter")
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
                @jsonutil.json_object([
                  ("type", @jsonutil.json_string("text")),
                  ("text", @jsonutil.json_string(text)),
                ])
              @types.Image(data, mime_type~) =>
                @jsonutil.json_object([
                  ("type", @jsonutil.json_string("image")),
                  ("data", @jsonutil.json_string(data)),
                  ("mimeType", @jsonutil.json_string(mime_type)),
                ])
              @types.ResourceLink(uri) =>
                @jsonutil.json_object([
                  ("type", @jsonutil.json_string("resource_link")),
                  ("uri", @jsonutil.json_string(uri)),
                ])
              @types.EmbeddedResource(content) => {
                let content_pairs : Array[(String, String)] = [
                  ("type", @jsonutil.json_string("resource")),
                ]
                match content {
                  @types.Text(text, uri~, mime_type~) => {
                    content_pairs.push(("uri", @jsonutil.json_string(uri)))
                    content_pairs.push(("text", @jsonutil.json_string(text)))
                    match mime_type {
                      Some(mt) =>
                        content_pairs.push(
                          ("mimeType", @jsonutil.json_string(mt)),
                        )
                      None => ()
                    }
                  }
                  @types.Blob(data, uri~, mime_type~) => {
                    content_pairs.push(("uri", @jsonutil.json_string(uri)))
                    content_pairs.push(("blob", @jsonutil.json_string(data)))
                    content_pairs.push(
                      ("mimeType", @jsonutil.json_string(mime_type)),
                    )
                  }
                }
                @jsonutil.json_object(content_pairs)
              }
            }
          })
          let result = @jsonutil.json_object([
            ("content", @jsonutil.json_array(content_items)),
            ("isError", @jsonutil.json_bool(tool_result.is_error)),
          ])
          @jsonutil.jsonrpc_success(id, result)
        }
        Err(e) => @jsonutil.jsonrpc_error(id, e.to_error_code(), e.message())
      }
    }
  }
}

///|
fn handle_resources_list(server : MCPServer, id : @types.RequestId) -> String {
  let resources = server.resource_registry.list_resources()
  let resource_jsons = resources.map(fn(resource) {
    let pairs : Array[(String, String)] = [
      ("uri", @jsonutil.json_string(resource.uri)),
      ("name", @jsonutil.json_string(resource.name)),
    ]
    match resource.description {
      Some(desc) => pairs.push(("description", @jsonutil.json_string(desc)))
      None => ()
    }
    match resource.mime_type {
      Some(mt) => pairs.push(("mimeType", @jsonutil.json_string(mt)))
      None => ()
    }
    @jsonutil.json_object(pairs)
  })
  let result = @jsonutil.json_object([
    ("resources", @jsonutil.json_array(resource_jsons)),
  ])
  @jsonutil.jsonrpc_success(id, result)
}

///|
async fn handle_resources_read(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let uri = @jsonutil.extract_string_from_json(params, "uri")
  match uri {
    None => @jsonutil.jsonrpc_error(id, -32602, "Missing 'uri' parameter")
    Some(uri_str) =>
      match server.resource_registry.read_resource(uri_str) {
        Ok(read_result) => {
          let content_json = match read_result.content {
            @resource.Text(text) =>
              @jsonutil.json_object([
                ("uri", @jsonutil.json_string(read_result.uri)),
                ("text", @jsonutil.json_string(text)),
              ])
            @resource.Blob(data, mime_type~) =>
              @jsonutil.json_object([
                ("uri", @jsonutil.json_string(read_result.uri)),
                ("blob", @jsonutil.json_string(data.to_string())),
                ("mimeType", @jsonutil.json_string(mime_type)),
              ])
          }
          let result = @jsonutil.json_object([
            ("contents", @jsonutil.json_array([content_json])),
          ])
          @jsonutil.jsonrpc_success(id, result)
        }
        Err(e) => @jsonutil.jsonrpc_error(id, e.to_error_code(), e.message())
      }
  }
}

///|
fn handle_resources_subscribe(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let uri = @jsonutil.extract_string_from_json(params, "uri")
  match uri {
    None => @jsonutil.jsonrpc_error(id, -32602, "Missing 'uri' parameter")
    Some(uri_str) =>
      match server.resource_registry.subscribe(uri_str) {
        Ok(_) => @jsonutil.jsonrpc_success(id, @jsonutil.json_object([]))
        Err(e) => @jsonutil.jsonrpc_error(id, e.to_error_code(), e.message())
      }
  }
}

///|
fn handle_resources_unsubscribe(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let uri = @jsonutil.extract_string_from_json(params, "uri")
  match uri {
    None => @jsonutil.jsonrpc_error(id, -32602, "Missing 'uri' parameter")
    Some(uri_str) =>
      match server.resource_registry.unsubscribe(uri_str) {
        Ok(_) => @jsonutil.jsonrpc_success(id, @jsonutil.json_object([]))
        Err(e) => @jsonutil.jsonrpc_error(id, e.to_error_code(), e.message())
      }
  }
}

///|
fn handle_prompts_list(server : MCPServer, id : @types.RequestId) -> String {
  let prompts = server.prompt_registry.list_prompts()
  let prompt_jsons = prompts.map(fn(prompt) {
    let pairs : Array[(String, String)] = [
      ("name", @jsonutil.json_string(prompt.name)),
    ]
    match prompt.description {
      Some(desc) => pairs.push(("description", @jsonutil.json_string(desc)))
      None => ()
    }
    match prompt.arguments {
      Some(args) => {
        let arg_jsons = args.map(fn(arg) {
          let arg_pairs : Array[(String, String)] = [
            ("name", @jsonutil.json_string(arg.name)),
          ]
          match arg.description {
            Some(d) => arg_pairs.push(("description", @jsonutil.json_string(d)))
            None => ()
          }
          match arg.required {
            Some(true) => arg_pairs.push(("required", "true"))
            _ => ()
          }
          @jsonutil.json_object(arg_pairs)
        })
        pairs.push(("arguments", @jsonutil.json_array(arg_jsons)))
      }
      None => ()
    }
    @jsonutil.json_object(pairs)
  })
  let result = @jsonutil.json_object([
    ("prompts", @jsonutil.json_array(prompt_jsons)),
  ])
  @jsonutil.jsonrpc_success(id, result)
}

///|
async fn handle_prompts_get(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let prompt_name = @jsonutil.extract_string_from_json(params, "name")
  match prompt_name {
    None => @jsonutil.jsonrpc_error(id, -32602, "Missing 'name' parameter")
    Some(name) =>
      match server.prompt_registry.get_prompt(name, params) {
        Ok(prompt_result) => {
          let messages_json = prompt_result.messages.map(fn(msg) {
            let content = match msg.content {
              @types.Text(text) =>
                @jsonutil.json_object([
                  ("type", @jsonutil.json_string("text")),
                  ("text", @jsonutil.json_string(text)),
                ])
              _ => "null" // Handle other content types if necessary
            }
            @jsonutil.json_object([
              ("role", @jsonutil.json_string(msg.role)),
              ("content", content),
            ])
          })
          let result = @jsonutil.json_object([
            (
              "description",
              prompt_result.description
              .map(@jsonutil.json_string)
              .unwrap_or("null"),
            ),
            ("messages", @jsonutil.json_array(messages_json)),
          ])
          @jsonutil.jsonrpc_success(id, result)
        }
        Err(e) => @jsonutil.jsonrpc_error(id, e.to_error_code(), e.message())
      }
  }
}

///|
fn handle_set_level(
  server : MCPServer,
  id : @types.RequestId,
  params : Json,
) -> String {
  let level = @jsonutil.extract_string_from_json(params, "level")
  match level {
    None => @jsonutil.jsonrpc_error(id, -32602, "Missing 'level' parameter")
    Some(lvl) => {
      server.log_level = Some(lvl)
      @jsonutil.jsonrpc_success(id, @jsonutil.json_object([]))
    }
  }
}
