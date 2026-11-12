///|
/// Feature tour of the MCP 2026-07-28 **server** API.
///
/// Tools
///   - `echo`   — trait-based registration (`impl Tool`), the shape to copy for
///                real logic
///   - `stats`  — `tool_definition` with an `output_schema`, so a successful
///                result must carry matching `structuredContent`
///   - `review` — multi-round-trip (MRTR): asks the client for an elicitation
///                form plus a sampling completion, then finishes on the retry
///   - `slow`   — reports progress notifications and honours
///                `notifications/cancelled`
///
/// Resources
///   - `memo://greeting`    static text
///   - `memo://notes/1`     concrete entry, plus the `memo://notes/{id}`
///                          template that `completion/complete` fills in
///
/// Prompts
///   - `summarize`   one required argument, rendered as a user message
///
/// Run with `moon run cmd/main` from `examples/server`: it speaks
/// newline-delimited JSON-RPC on stdin/stdout, so a client is required to see
/// anything. `examples/client` starts it automatically.

///|
/// Trait-based tool, the shape to copy for tools with real logic.
struct EchoTool {}

///|
impl @mcp.Tool for EchoTool with fn name(_) -> String {
  "echo"
}

///|
impl @mcp.Tool for EchoTool with fn description(_) -> String {
  "Echo back the input text"
}

///|
impl @mcp.Tool for EchoTool with fn params(_) -> Array[@mcp.ParamDef] {
  [
    {
      name: "text",
      description: "Text to echo back",
      type_: "string",
      required: true,
    },
  ]
}

///|
impl @mcp.Tool for EchoTool with fn execute(_, _context, args : Json) -> @mcp.ToolCallOutcome {
  match @mcp.get_string(args, "text") {
    Ok(text) => @mcp.ToolCallOutcome::Complete(@mcp.ToolResult::text(text))
    Err(_) =>
      @mcp.ToolCallOutcome::Complete(
        @mcp.ToolResult::error("Missing 'text' parameter"),
      )
  }
}

///|
/// `values` is already validated against the declared input schema.
fn stats_values(args : Json) -> Array[Double] {
  match args {
    Object(fields) =>
      match fields.get("values") {
        Some(Array(items)) =>
          items.map(item => {
            match item {
              Number(value, ..) => value
              _ => 0.0
            }
          })
        _ => []
      }
    _ => []
  }
}

///|
async fn main {
  let stats_definition = @mcp.ToolDefinition::new(
    "stats",
    {
      "type": "object",
      "properties": {
        "values": { "type": "array", "items": { "type": "number" } },
      },
      "required": ["values"],
    },
    title="Numeric stats",
    description="Count, sum and mean of a list of numbers",
    output_schema={
      "type": "object",
      "properties": {
        "count": { "type": "integer" },
        "sum": { "type": "number" },
        "mean": { "type": "number" },
      },
      "required": ["count", "sum", "mean"],
      "additionalProperties": false,
    },
    annotations=@mcp.ToolAnnotations::new(read_only_hint=true),
  )
  let review_definition = @mcp.ToolDefinition::new(
    "review",
    {
      "type": "object",
      "properties": { "text": { "type": "string" } },
      "required": ["text"],
    },
    description="Ask the client for approval and a draft before answering",
  )
  let slow_definition = @mcp.ToolDefinition::new(
    "slow",
    { "type": "object", "properties": {} },
    description="Five progress steps, cancellable",
  )
  let completions = @mcp.CompletionRegistry::new().register(
    @mcp.CompletionReference::resource("memo://notes/{id}"),
    (_context, _params) => {
      Ok(@mcp.CompletionResult::new(["1", "2", "3"], has_more=false))
    },
  )
  let server = @mcp.MCPServer("example-server", "1.0.0")
    .with_title("MCP example server")
    .with_description(
      "Tools, resources, prompts, completion and MRTR over stdio.",
    )
    .with_instructions("Start with tools/list, then try the review tool.")
    // MRTR needs a requestState codec: without one the runtime refuses to seal
    // continuation state and the tool fails with -32603. Use a real key from
    // your secret store, and the same key across instances sharing state.
    .with_request_state_codec(
      @server.AesGcmStateCodec::with_key(
        Bytes::from_array([
          0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
          0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
          0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
        ]),
      ),
    )
    .with_tool(EchoTool::{ })
    .tool_definition(stats_definition, fn(_context, args) {
      let values = stats_values(args)
      let sum = values.fold(init=0.0, (acc, value) => acc + value)
      let mean = if values.is_empty() {
        0.0
      } else {
        sum / values.length().to_double()
      }
      // `output_schema` is declared, so the SDK verifies this object before
      // publishing it; a missing or mistyped field becomes -32603.
      Ok(
        @mcp.ToolCallOutcome::Complete(
          @mcp.ToolResult::structured({
            "count": values.length(),
            "sum": sum,
            "mean": mean,
          }),
        ),
      )
    })
    .tool_definition(review_definition, (context, args) => {
      let text = @mcp.get_string(args, "text").unwrap_or("")
      // No answers yet: publish the requests and the business state to restore.
      // The runtime seals `state` into `requestState`; the retry sees the
      // client's answers in `context.input_responses`, never in `args`.
      if context.input_responses.is_empty() {
        let form = @mcp.ElicitationRequest::form(
          "Approve reviewing this text?",
          {
            "type": "object",
            "properties": {
              "approved": { "type": "boolean" },
              "note": { "type": "string" },
            },
            "required": ["approved"],
          },
        )
        let sampling = @mcp.CreateMessageRequest::new(
          [
            @mcp.SamplingMessage::new(
              @mcp.Role::User,
              @mcp.SamplingContent::text("Draft one sentence about: " + text),
            ),
          ],
          64,
        )
        let requests : Map[String, @mcp.InputRequestEntry] = Map::from_array([
          (
            "approval",
            {
              method_name: @mcp.InputRequestKind::ElicitationCreate,
              params: form.to_json(),
            },
          ),
          (
            "draft",
            {
              method_name: @mcp.InputRequestKind::SamplingCreateMessage,
              params: sampling.to_json(),
            },
          ),
        ])
        return Ok(
          @mcp.ToolCallOutcome::InputRequired(input_requests=requests, state={
            "text": text,
          }),
        )
      }
      // The SDK already checked the keys, the result types and the form content.
      let approved = match context.input_responses.get("approval") {
        Some(Object(fields)) =>
          match fields.get("action") {
            Some(String(action)) => action == "accept"
            _ => false
          }
        _ => false
      }
      if !approved {
        return Ok(
          @mcp.ToolCallOutcome::Complete(
            @mcp.ToolResult::text("Review declined by the client"),
          ),
        )
      }
      let draft = match context.input_responses.get("draft") {
        Some(value) => value.stringify()
        None => "no draft"
      }
      Ok(
        @mcp.ToolCallOutcome::Complete(
          @mcp.ToolResult::text("Approved. Sampling result: " + draft),
        ),
      )
    })
    .tool_definition(slow_definition, (context, _args) => {
      let mut step = 0
      while step < 5 {
        step = step + 1
        // The runtime cannot preempt a running handler: check the token and
        // yield so a cancelled call stops instead of running to completion.
        context.cancellation_token.throw_if_cancelled()
        context.progress_reporter.report(
          step.to_double(),
          total=5.0,
          message="step \{step} of 5",
        )
        @async.sleep(200)
      }
      Ok(
        @mcp.ToolCallOutcome::Complete(
          @mcp.ToolResult::text("finished 5 steps"),
        ),
      )
    })
    .resource(
      "memo://greeting",
      "greeting",
      "A static greeting",
      "text/plain",
      fn(_context) {
        Ok(
          @mcp.ResourceReadResult::text(
            "Hello from the MCP example server.\n",
            uri="memo://greeting",
            mime_type="text/plain",
          ),
        )
      },
    )
    .resource("memo://notes/1", "note-1", "Note 1", "text/plain", fn(_context) {
      Ok(
        @mcp.ResourceReadResult::text(
          "A note that the completion handler can also suggest by id.\n",
          uri="memo://notes/1",
          mime_type="text/plain",
        ),
      )
    })
    .resource_template(
      uri_template="memo://notes/{id}",
      name="note",
      description="A note by id",
      mime_type="text/plain",
    )
    .prompt(
      "summarize",
      "Build a summarization prompt",
      [
        @mcp.PromptArgument::new(
          "text",
          description="Text to summarize",
          required=true,
        ),
      ],
      fn(_context, args) {
        let text = @mcp.get_string(args, "text").unwrap_or("")
        Ok(
          @mcp.GetPromptResult::new([
            @mcp.PromptMessage::new(
              @mcp.Role::User,
              @mcp.ContentBlock::text(
                "Summarize the following in one sentence:\n" + text,
              ),
            ),
          ]),
        )
      },
    )
    .with_completions(completions)
  server.run_stdio()
}
