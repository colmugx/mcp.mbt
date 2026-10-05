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

Tool, resource, and prompt registration use the facade; no extra protocol-package import is needed for the examples below.

```moonbit
let server = @mcp.MCPServer("app", "1.0.0")
  .with_title("App Server")
  .with_description("Demo of the builder API.")
  .with_instructions("How the model should use this server.")
  // tools/call: positional (name, description, input schema, handler)
  .tool("echo", "Echo its input", Json::object({ "type": "object" }), fn(_context, args) {
    Ok(@mcp.ToolResult::text(args.stringify()))
  })
  // resources/read: (uri, name, description, mime type, handler)
  .resource(
    "memo://greeting",
    "greeting",
    "A static greeting",
    "text/plain",
    fn(_context) {
      Ok(@mcp.ResourceReadResult::text("hello", uri="memo://greeting", mime_type="text/plain"))
    },
  )
  // prompts/get: (name, description, argument defs, handler)
  .prompt("greet", "Build a greeting", [], fn(_context, _args) {
    Ok(@mcp.GetPromptResult::new([
      @mcp.PromptMessage::new(@mcp.Role::User, @mcp.ContentBlock::text("Hi!")),
    ]))
  })
  // resources/templates/list
  .resource_template(
    uri_template="memo://{id}",
    name="memo",
    description="A memo by id",
    mime_type="text/plain",
  )
```

Content blocks, tool definitions/results, resource definitions/templates/contents/read results, and prompt definitions/arguments/messages/results are all available through `@mcp`. Their owning wire-model package is `protocol/types`; specialized protocol packages re-export the relevant models.

Handlers are async and return `Result`; a failed tool computation should be reported inside the tool result (`ToolResult::error`, with `is_error` on the wire), while protocol problems (unknown tool, invalid arguments) become JSON-RPC errors automatically.

## Full tool definitions and structured output

Use `tool_definition` when you need an output schema, annotations, icons, or tool metadata. It keeps the full wire definition instead of reconstructing it from parameter helpers:

```moonbit
let definition = @mcp.ToolDefinition::new(
  "numbers",
  { "type": "object", "additionalProperties": false },
  title="Numbers",
  output_schema={ "type": "array", "items": { "type": "integer" } },
  annotations=@mcp.ToolAnnotations::new(read_only_hint=true),
)
let server = @mcp.MCPServer("app", "1.0.0")
  .tool_definition(definition, (_context, _args) => {
    Ok(@mcp.ToolCallOutcome::Complete(@mcp.ToolResult::structured([1, 2, 3])))
  })
```

The result codec emits `structuredContent` and preserves handler `_meta` keys and top-level extensions. Server-owned identity is added to `_meta` without mutating the handler's result.

### Enforced input and output contracts

Registration owns a snapshot of each definition and compiles its schemas once. Malformed
or unsupported schemas raise `MCPError::InvalidParams` immediately; a failed replacement
leaves the old tool intact. Before a handler runs, arguments must satisfy `inputSchema`:
unknown tools and invalid arguments return `-32602`, without executing tool side effects.
MRTR retries check the same business arguments; client answers are accessed through
`context.input_responses`, not extra argument properties.

When `output_schema` is declared, a successful complete result must have matching
`structuredContent`. Missing or invalid structured output returns `-32603`; explicit
JSON null remains a present value and is valid only if the schema permits it. Tool
failures (`ToolResult::error`, `isError: true`) and `InputRequired` are not treated as
successful output needing validation. Without an output schema, structured output is
still preserved.

The validator supports closed objects, arrays, combinators, exact numeric constraints
and local static `$ref`/`$defs`, including bounded recursive schemas. It does not yet
support remote references, `$id`/anchors, dynamic references, unevaluated semantics or
arbitrary regex patterns; `format` is annotation-only. Registration rejects unsupported
semantics rather than silently ignoring them. Check the [support contract](../../docs/conformance.md)
before exposing a schema from another generator.

Load precise numeric schemas/results with `@mcp.parse_json(text)` instead of first
rounding them through another JSON parser. SDK request/result wire parsing preserves
number lexemes automatically, but cannot recover precision lost before the value
reaches the SDK. For CPU-heavy or untrusted schemas, also respect the validator's
depth and regex-profile limits; validation is not an arbitrary-pattern sandbox.

## Multiple resource contents

A read returns a `ResourceReadResult` with `contents`, not a single `uri`/`content` pair. Each entry may be text or a base64 blob, with its own URI, optional MIME type, and metadata:

```moonbit
let result = @mcp.ResourceReadResult::new([
  @mcp.ResourceContents::text("hello", uri="memo://1", mime_type="text/plain"),
  @mcp.ResourceContents::blob("aGk=", uri="memo://2"),
])
```

Use `resource_definition(definition, handler)` or `resource_template_definition(definition)` when advertising titles, icons, annotations, or metadata. Existing simple `resource`/`resource_template` registration helpers remain available. A blob without `mimeType` stays without it; the SDK does not invent a MIME type.

For cacheable resource results, set `result.metadata.ttl_ms` and `cache_scope` when your handler has more accurate hints. Explicit hints (including TTL zero) survive publication; SDK defaults fill only absent hints. Use public cache scope only for results independent of credentials or user-specific data. Invalid metadata or known handler result shapes are returned as internal errors rather than published as malformed successes.

## Prompt metadata

`PromptArgument::new(name, title~, description~, required~)` keeps explicit `required=false` distinct from omission. Build messages with `PromptMessage::new(Role::User, content)` and results with `GetPromptResult::new(messages, description~, metadata~)`.

For titles, icons, or metadata on a prompt definition, use `prompt_definition(definition, handler)`. Standard prompt definitions do not define `annotations`; vendor annotations can be retained in their `extensions` map without treating them as standard fields. Prompt get results preserve result metadata and message-level extensions through the shared codecs.

## Trait-based registration

For tools and resources with real logic, implement the `Tool`, `Resource`, or `Prompt` trait and hand the value to `with_tool`, `with_resource`, or `with_prompt`. A `Tool`'s `execute` returns `ToolCallOutcome`, so the same trait covers both plain tools and tools that suspend for client input:

```moonbit
///|
impl @mcp.Tool for MyTool with fn execute(self, context, args) -> @mcp.ToolCallOutcome {
  // Complete(result) finishes normally; InputRequired(..) asks the client
  // for input, then the request is retried with the answers attached.
  ...
}
```

`MCPServer::prompt_mrtr` and `MCPServer::resource_mrtr` (plus the `with_prompt_mrtr` / `with_resource_mrtr` trait variants) are the MRTR-aware equivalents for prompts and resources.

## Advertised capabilities

A new server exposes discovery but does not advertise empty tools, resources, or prompts registries by default. Registration enables the corresponding capability automatically; registering a resource template also enables resources. `server.capabilities()` is the same typed view published by `server/discover`.

If an intentionally empty registry is part of your API, enable it explicitly:

```moonbit
let server = @mcp.MCPServer("app", "1.0.0")
  .with_tools()
  .with_resources()
  .with_prompts()
```

These methods return empty lists until entries are registered. Pass `enabled=false` to disable a feature even if its registry contains entries; its methods then return `-32601` rather than accepting calls against an unadvertised capability. Disabling does not delete registrations. Completion uses `with_completions(registry)` separately. Subscription acknowledgments agree only the notification types supported by enabled features. Logging and experimental capabilities are not advertised merely because their wire types exist.

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

`AuthConfig::AuthConfig(authenticate~, resource_metadata_url~, ...)` replaces the old Bool-returning `verify_token` hook. Return `Some(Principal)` only after validating the bearer token and any required scopes; return `None` to reject it. The trusted identity arrives as `context.principal` and binds MRTR continuation state. Never derive this identity from client `_meta`.

```moonbit
let auth = @transport.AuthConfig(
  authenticate=fn(token) {
    if token == expected_token {
      Some(@mcp.Principal::new("account-42", scopes=["tools:read"]))
    } else {
      None
    }
  },
  resource_metadata_url="https://example.com/.well-known/oauth-protected-resource",
  required_scopes="tools:read",
)
```

Import `colmugx/mcp/transport` for `@transport`. The example illustrates the return type, not production token verification: use your identity provider's signature, expiry, issuer, audience, and scope checks. `required_scopes` is an authentication-challenge advertisement, not automatic enforcement. OAuth client authorization, PKCE, registration, and refresh remain out of scope. See the [transport reference](04-transport-reference.md) for Origin rules.

## Runtime behavior

Each JSON-RPC request is parsed once, then dispatched by method.

Handled inline (no spawn):

- `server/discover`
- `tools/list`, `resources/list`, `resources/templates/list`, `prompts/list`

`initialize` is a legacy method and is rejected by the modern server. `ping` is not a modern dispatch method.

Spawned on the task group (the handler may suspend):

- `tools/call`, `resources/read`, `prompts/get`, `completion/complete`

Stdio responses are serialized through one output queue. HTTP requests carry an authenticated envelope with a request-local reply queue, identity, and cancellation token, so out-of-order completion cannot cross responses. Every request needs `_meta.io.modelcontextprotocol/protocolVersion` and `_meta.io.modelcontextprotocol/clientCapabilities`; connect/call helpers supply these automatically.

## Request context, MRTR, and cancellation

Handlers now receive `RequestContext` before their business arguments. Simple resources receive the context alone. Trait methods similarly become `execute(self, context, arguments)`, `read(self, context)`, or `get(self, context, arguments)`. The context carries request id, metadata, trusted principal, `input_responses`, restored `continuation_state`, a cancellation token, and a progress reporter. MRTR input responses are **never** injected into business arguments; use `context.input_responses` rather than `_mrtr_responses`.

Enable opaque MRTR continuation state with `with_request_state_codec(AesGcmStateCodec)` (import `colmugx/mcp/server` for the codec). The default expiry clock is real Unix time; `with_clock` is for deterministic tests. On retry, state is checked against principal, method, salient parameters (including the tool name), integrity, and expiry before the handler runs. A valid same-operation retry may repeat within its lifetime: the runtime is stateless, not an exactly-once side-effect service. Make externally visible tool effects idempotent when appropriate.

The runtime validates handler-authored elicitation/sampling/roots requests before issuing `input_required`; malformed server output produces `-32603`. Form elicitation must provide a restricted object schema with `properties`. The authenticated state also records the requested input keys and definitions. A retry must supply exactly those keys, matching each requested result type and any form constraints, or receive `-32602` before your handler is called. `context.continuation_state` still contains only your original business state; the correlation envelope is internal. Previously issued blobs without this envelope cannot resume after upgrading, so deploy instances sharing keys and a compatible runtime together.

This is validation, not consent automation: your client handler owns user interaction, sensitive-data policy, and URL navigation. Form `format` and `default` fields are annotations, not automatic format checks or submitted defaults.

Stdio `notifications/cancelled` cancels the matching in-flight task in that transport's scope. The cancelled task emits no final response or later progress. HTTP SSE streams use periodic keepalive flushes to detect disconnect; I/O failure cancels that request and closes its reply queue. Detection is bounded by keepalive cadence and socket failure reporting, not instantaneous. For CPU-bound loops, call `context.cancellation_token.throw_if_cancelled()` and yield periodically; no runtime can preempt a non-yielding synchronous computation.

## Completion

Enable completion explicitly, including an empty registry if your server supports the method but has no suggestions:

```moonbit
let completions = @mcp.CompletionRegistry::new().register(
  @mcp.CompletionReference::resource("memo://{id}"),
  (_context, params) => {
    // params.argument holds the value being completed;
    // params.context.arguments carries previously resolved variables.
    Ok(@mcp.CompletionResult::new(["memo-1", "memo-2"], has_more=false))
  },
)
let server = @mcp.MCPServer("app", "1.0.0").with_completions(completions)
```

An enabled registry advertises `completions: {}`; a disabled registry returns `-32601`. Results preserve metadata and extension fields, and more than 100 suggestions are rejected rather than silently truncated.
