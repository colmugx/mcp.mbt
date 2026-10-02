# 3. Server Guide

Build servers with `MCPServer(name, version)` and chain the builder methods. Every `with_*`/registration method returns the server, so a complete setup reads top-to-bottom.

All snippets assume:

```moonbit
import {
  "colmugx/mcp",
  "moonbitlang/async",
}
```

## Register capabilities

Tool registration only needs the facade. Prompt and resource handlers construct result types from the protocol packages, so import them when you register those:

```moonbit
import {
  "colmugx/mcp/protocol/types",
  "colmugx/mcp/protocol/resource",
}
```

```moonbit
let server = @mcp.MCPServer("app", "1.0.0")
  .with_title("App Server")
  .with_description("Demo of the builder API.")
  .with_instructions("How the model should use this server.")
  // tools/call: positional (name, description, input schema, handler)
  .tool("echo", "Echo its input", Json::object({}), fn(args) {
    Ok(@mcp.ToolResult::text(args.stringify()))
  })
  // resources/read: (uri, name, description, mime type, handler)
  .resource(
    "memo://greeting",
    "greeting",
    "A static greeting",
    "text/plain",
    fn() {
      Ok({
        uri: "memo://greeting",
        content: @resource.ResourceContent::Text("hello"),
      })
    },
  )
  // prompts/get: (name, description, argument defs, handler)
  .prompt("greet", "Build a greeting", [], fn(_args) {
    Ok({
      description: None,
      messages: [
        {
          role: "user",
          content: @types.ContentBlock::text("Hi!"),
        },
      ],
    })
  })
  // resources/templates/list
  .resource_template(
    uri_template="memo://{id}",
    name="memo",
    description="A memo by id",
    mime_type="text/plain",
  )
```

Note the two spellings above: `@types.ContentBlock` works through the facade as `@mcp.ContentBlock`, but `GetPromptResult` / `PromptMessage` / `ResourceReadResult` / `ResourceContent` are not re-exported by the facade, so prompt and resource handlers need the `@types` / `@resource` imports shown above.

Handlers are async and return `Result`; a failed tool computation should be reported inside the tool result (`ToolResult::error`, with `is_error` on the wire), while protocol problems (unknown tool, invalid arguments) become JSON-RPC errors automatically.

## Trait-based registration

For tools and resources with real logic, implement the `Tool`, `Resource`, or `Prompt` trait and hand the value to `with_tool`, `with_resource`, or `with_prompt`. A `Tool`'s `execute` returns `ToolCallOutcome`, so the same trait covers both plain tools and tools that suspend for client input:

```moonbit
///|
impl @mcp.Tool for MyTool with fn execute(self, args) -> @mcp.ToolCallOutcome {
  // Complete(result) finishes normally; InputRequired(..) asks the client
  // for input, then the request is retried with the answers attached.
  ...
}
```

`MCPServer::prompt_mrtr` and `MCPServer::resource_mrtr` (plus the `with_prompt_mrtr` / `with_resource_mrtr` trait variants) are the MRTR-aware equivalents for prompts and resources.

## Run modes

```moonbit
server.run_stdio()                        // newline-delimited JSON-RPC on stdin/stdout
server.run_http(port=4240, path="/mcp")   // Streamable HTTP + SSE
```

Both are async and raise `TransportError`. The runtime owns transport dispatch, task-group lifecycle, and response routing — you never construct a transport yourself.

## Authentication

```moonbit
server
  .with_auth(auth) // @transport.AuthConfig
  .run_http(port=4240, path="/mcp")
```

`AuthConfig` carries `verify_token`, optional `allowed_origins`, `required_scopes`, `authorization_servers`, and a protected-resource metadata URL. See the [transport reference](04-transport-reference.md) for origin-checking rules.

## Runtime behavior

Each JSON-RPC request is parsed once, then dispatched by method.

Handled inline (no spawn):

- `initialize`, `ping`
- `tools/list`, `resources/list`, `prompts/list`

Spawned on the task group (the handler may suspend):

- `tools/call`, `resources/read`, `prompts/get`

Stdio responses are serialized through one output queue. HTTP requests each carry their own reply queue, so responses return to the matching request even when handlers complete out of order.
