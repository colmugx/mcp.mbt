///|
/// Feature tour of the MCP 2026-07-28 **client** API.
///
/// Phase 1 uses one `MCPClient` against the stdio server in
/// `examples/server` and walks through the feature surface: discovery, tools
/// (plain, structured output, MRTR, progress), resources, resource templates,
/// prompts and completion.
///
/// Phase 2 uses `MCPHost` for the multi-server case: the same stdio server plus
/// an optional Streamable HTTP server, with tool names qualified per
/// connection.
///
/// Run from `examples/client`, not the repository root: the stdio child is
/// launched with the relative path `../server/cmd/main`.

///|
/// Print the text content of a tool result, then its structured content.
fn print_result(label : String, result : @mcp.CallToolResult) -> Unit {
  println("\{label}: is_error=\{result.is_error.unwrap_or(false)}")
  for block in result.content {
    match block {
      @mcp.ContentBlock::Text(text, ..) => println("  text: \{text}")
      _ => ()
    }
  }
  if result.structured_content is Some(value) {
    println("  structured: \{value.stringify()}")
  }
}

///|
#warnings("-cancellable_defer")
async fn main {
  @async.with_task_group(group => {
    // Registering these handlers is what advertises the client capabilities.
    let client = @mcp.MCPClient::connect_stdio(
        cmd="moon",
        args=["run", "../server/cmd/main"],
        name="example-client",
        version="1.0.0",
        group~,
      )
      .on_elicitation(fn(_params) {
        // A form handler owns the user interaction. `Accept` requires content
        // that satisfies the requested schema.
        Ok(
          @mcp.ElicitationResult::new(
            @mcp.ElicitationAction::Accept,
            content=Map::from_array([
              ("approved", @mcp.ElicitationValue::Boolean(true)),
              ("note", @mcp.ElicitationValue::String("looks fine")),
            ]),
          ),
        )
      })
      .on_sampling(fn(_params) {
        Ok(
          @mcp.CreateMessageResult::text(
            "example-model", "A short draft written by the client.",
          ),
        )
      })
      .on_notification({
        ..@client.NotificationHandlers::empty(),
        on_progress: Some(fn(notification) {
          let total = match notification.total {
            Some(value) => value.as_double().to_string()
            None => "?"
          }
          println(
            "  progress \{notification.progress.as_double()}/\{total} \{notification.message.unwrap_or("")}",
          )
        }),
      })
    defer @async.protect_from_cancel(() => client.close())

    let discovery = client.discover_result()
    println("supported versions: \{discovery.supported_versions.join(", ")}")
    println("instructions: \{discovery.instructions.unwrap_or("(none)")}")

    let tools = client.list_tools()
    println(
      "\{tools.tools.length()} tools: \{tools.tools.map(fn(tool) { tool.name }).join(", ")}",
    )
    print_result(
      "echo",
      client.call_tool("echo", arguments="{\"text\":\"hello\"}"),
    )

    // The server declares an output schema, so `structuredContent` arrives
    // already validated against it.
    print_result(
      "stats",
      client.call_tool("stats", arguments="{\"values\":[1,2,3,4]}"),
    )

    // MRTR: the tool answers `input_required`, the client runs the handlers
    // above and retries the request automatically.
    print_result(
      "review",
      client.call_tool("review", arguments="{\"text\":\"quarterly numbers\"}"),
    )

    // `progress_token` correlates the `on_progress` notifications with this call.
    print_result(
      "slow",
      client.call_tool(
        "slow",
        arguments="{}",
        progress_token=@mcp.ProgressToken::String("slow-1"),
      ),
    )

    let resources = client.list_resources()
    for resource in resources.resources {
      println("resource: \{resource.uri}")
    }
    let greeting = client.read_resource("memo://greeting")
    for content in greeting.contents {
      match content.data {
        @mcp.ResourceData::Text(text) => println("  greeting: \{text}")
        _ => ()
      }
    }
    let templates = client.list_resource_templates()
    for template in templates.resource_templates {
      println("template: \{template.uri_template}")
    }

    let prompts = client.list_prompts()
    for prompt in prompts.prompts {
      println("prompt: \{prompt.name}")
    }
    let rendered = client.get_prompt(
      "summarize",
      arguments="{\"text\":\"MCP is a protocol for tools and context.\"}",
    )
    for message in rendered.messages {
      match message.content {
        @mcp.ContentBlock::Text(text, ..) =>
          println("  prompt message: \{text}")
        _ => ()
      }
    }

    let completion = client.complete(
      ref_type="ref/resource",
      ref_name="memo://notes/{id}",
      argument_name="id",
      argument_value="",
    )
    println("completion suggestions: \{completion.values.join(", ")}")
  })

  // Multiple servers behind one host: tool names are qualified per connection,
  // so two servers may expose the same tool name.
  let host = @mcp.MCPHost::MCPHost(name="example-host", version="1.0.0")
  @async.with_task_group(group => {
    defer @async.protect_from_cancel(() => host.close_all())
    try
      host.connect_stdio(
        name="local",
        cmd="moon",
        args=["run", "../server/cmd/main"],
        group~,
      )
    catch {
      @mcp.MCPError::_ as error => println("[local] failed: \{error.message()}")
      error => raise error
    } noraise {
      _ => println("[local] connected")
    }
    // Optional: run examples/http first to see this connection succeed.
    try
      host.connect_http(name="remote", url="http://localhost:4240/mcp")
    catch {
      @mcp.MCPError::_ as error =>
        println("[remote] failed: \{error.message()}")
      error => raise error
    } noraise {
      _ => println("[remote] connected")
    }
    let tools = host.list_tools()
    println(
      "\{tools.tools.length()} host tools: \{tools.tools.map(fn(tool) { tool.name }).join(", ")}",
    )
    print_result(
      "local.echo",
      host.call_tool("local.echo", arguments="{\"text\":\"via host\"}"),
    )
  })
}
