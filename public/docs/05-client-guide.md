# 5. Client Guide

`MCPClient` talks to one MCP server. The connect helpers create the transport and complete the 2026-07-28 capability discovery before returning — there is no separate initialize call to make.

All snippets assume:

```moonbit
import {
  "colmugx/mcp",
  "colmugx/mcp/client",
  "moonbitlang/async",
  "moonbitlang/core/debug",
}
```

`colmugx/mcp/client` (alias `@client`) is needed for `ProtocolEra` and `NotificationHandlers`, which the facade does not re-export.

## Connect

```moonbit
let client = match
  @mcp.MCPClient::connect_http(
    url="http://localhost:4240/mcp",
    name="client",
    version="1.0.0",
  ) {
  Ok(c) => c
  Err(e) => abort("connect failed: \{e.message()}")
}
```

Stdio connections need a task group because the child process lifecycle belongs to async supervision:

```moonbit
@async.with_task_group(group => {
  match
    @mcp.MCPClient::connect_stdio(
      cmd="moon",
      args=["run", "server"],
      name="client",
      version="1.0.0",
      group~,
    ) {
    Ok(client) => client.close()
    Err(e) => println(e.message())
  }
})
```

### Protocol era

Servers speaking the older 2025-11-25 revision are still common. The optional `era~` parameter controls how connect handles them:

| Era | Behavior |
|-----|----------|
| `Auto` (default) | Probe with `server/discover`; silently fall back to the legacy handshake for 2025-11-25 servers. |
| `Legacy` | Skip the probe; speak the legacy handshake directly. |
| `Modern` | Probe; treat any legacy signal as a connection error instead of downgrading. |

```moonbit
let client = @mcp.MCPClient::connect_http(
  url="http://localhost:4240/mcp",
  name="client",
  version="1.0.0",
  era=@client.ProtocolEra::Modern,
)
```


## Calls

The client methods you will use most:

- `list_tools(cursor?)` / `call_tool(name, arguments?, progress_token?)`
- `list_resources(cursor?)` / `read_resource(uri)` / `list_resource_templates(cursor?)`
- `list_prompts(cursor?)` / `get_prompt(name, arguments?)`
- `complete(ref_type~, ref_name~, argument_name~, argument_value~, context_arguments?)`
- `complete_reference(CompletionReference, argument_name~, argument_value~, context_arguments?)` — typed prompt/resource references
- `discover()` — re-fetch server capabilities; `discover_result()` — retain supported versions, instructions and result metadata too
- `cancel_request(RequestId, reason?)` — release a locally owned request; stdio also sends `notifications/cancelled`, while HTTP closes that request's response stream
- `close()`

```moonbit
match client.call_tool("echo", arguments="{\"text\":\"hello\"}") {
  Ok(result) =>
    for block in result.content {
      println(@debug.to_string(block))
    }
  Err(e) => println(e.message())
}
```

`arguments` is the JSON-encoded arguments object. Invalid JSON or a non-object is rejected before sending; it is never silently replaced by `{}`. `CallToolResult` is an alias of the shared protocol `ToolResult`: it retains arbitrary JSON `structured_content` and result `metadata`; use `result.is_error.unwrap_or(false)` for the effective error flag.

For HTTP connections, `list_tools` excludes tools with invalid `x-mcp-header` annotations and logs a warning, as the protocol requires; valid definitions remain available. Mirrored headers are learned from the accepted definitions. This specific exclusion is distinct from malformed standard wire fields, which fail decoding.

`list_tools` retains cache hints, `_meta`, server identity and unknown result fields in `metadata`. Use `discover_result` when making cache or identity decisions; `discover` is the capabilities-only convenience view. The SDK preserves cache hints but does not implement an automatic cache.

Ordinary JSON-RPC error responses retain the peer's `code`, `message`, and `data` in `MCPError::RemoteError`. Inspect `to_error_code()` and `to_error_data()` to distinguish invalid arguments, unavailable methods and implementation-defined failures; do not classify every peer error as an internal SDK failure.

`read_resource` returns `ReadResourceResult` with a `contents` array of `ResourceContents`. Each entry carries `uri`, optional `mime_type`, `data` (`ResourceData::Text` or `ResourceData::Blob`), its own `_meta`, and extensions. Multiple text/blob entries are retained and a missing MIME type is not replaced with a default. Resource reads/lists/template lists expose result `metadata`, including cache hints and `_meta`. Malformed known entries fail the operation instead of silently disappearing. `list_prompts` similarly preserves full prompt definitions and result metadata; `get_prompt` returns a `GetPromptResult` that retains message extensions and result metadata.

## Notifications and subscriptions

Notifications never wake pending requests; out-of-order responses are routed by id. Register handlers with a `NotificationHandlers` value — every field is optional, start from `empty()` and fill in what you need:

```moonbit
let handlers = {
  ..@client.NotificationHandlers::empty(),
  on_progress: Some(fn(p) { println("progress \{p.progress}") }),
}
let client = client.on_notification(handlers)
```

Available hooks: `on_tools_changed`, `on_resources_changed`, `on_prompts_changed`, `on_progress`, `on_cancelled`, `on_resource_updated`, and `on_message` for anything unrecognized.

Ordinary calls also route notifications and responses correctly **without** starting `run()`: a temporary, single-reader pump invokes notification handlers and sends each response to its matching request queue. A progress event is never returned as the tool result or left to contaminate the next call. Concurrent calls can complete out of order. The persistent event loop is still required for `listen`, not for one-shot calls or their request-scoped progress.

For multiplexed subscriptions on one long-lived request, start `client.run(group)` before calling `listen(filter?, handler~, group~)`. It returns a subscription id. `cancel_listen(id)` cancels the owned subscription request on stdio or HTTP; it does not send a cross-request HTTP cancellation POST.

Cancellation preserves request-id types: use `RequestId::Int(7)` for a numeric id, not `RequestId::Str("7")`. Explicit cancellation returns a local `MCPError::Cancelled` to the waiting caller. Cancelling the calling async task instead propagates the runtime cancellation error. An HTTP id not owned by this client cannot be cancelled through `cancel_request`.

Progress tokens use `ProgressToken::String` or `ProgressToken::Number`. `call_tool(..., progress_token=ProgressToken::Number(7.5))` keeps the token numeric in request metadata and progress callbacks; it is not truncated or converted to a string.

Completion results expose `values`, optional numeric `total`, `has_more`, nested completion extensions, and result `metadata`. The protocol defines `total` as a number, so the SDK retains it as `Double?` rather than truncating to an `Int`. For resource templates, `complete(ref_type="ref/resource", ref_name="memo://{id}", ...)` emits a `uri` reference (not `name`). Use the typed `CompletionReference::prompt` / `resource` builders when possible; `context_arguments` supplies already resolved prompt/template variables.

## Client input handlers: modern MRTR and legacy callbacks

In modern MCP 2026-07-28, sampling, roots, and elicitation are fulfilled as inputs in an `input_required` result. `call_tool`, `read_resource`, and `get_prompt` run the MRTR loop: invoke your registered handlers, then retry with the returned inputs and opaque `requestState`. This one-shot flow does not require the event loop. Register handlers before starting calls:

```moonbit
let client = client
  .on_sampling(fn(_params) {
    Ok(@mcp.CreateMessageResult::text("m", "hi"))
  })
  .on_roots(fn() { Ok([]) })
  .on_elicitation(fn(_params) {
    Ok(@mcp.ElicitationResult::new(@mcp.ElicitationAction::Cancel))
  })

```

Handler signatures: `on_sampling((Json) -> Result[CreateMessageResult, MCPError])`, `on_roots(() -> Result[Array[Root], MCPError])`, `on_elicitation((Json) -> Result[ElicitationResult, MCPError])`. In modern mode, a missing handler produces `MissingRequiredClientCapability` for the original call; it is not a server-to-client JSON-RPC callback.

For **legacy** servers only, `client.run(group)` routes server-initiated sampling/roots/elicitation requests to those handlers and returns `-32601` when a handler is absent. Modern mode rejects direct server-initiated requests with `-32601` even when an MRTR handler is registered. The event loop is still needed for modern notification/subscription dispatch:

```moonbit
@async.with_task_group(group => {
  group.spawn_bg(() => { client.run(group) })
  // Make calls or start listen subscriptions while this group is alive.
})
```

A new client advertises no sampling, roots, or elicitation support until the corresponding handler is registered. Registering elicitation enables form mode by default. Capability codecs retain `experimental`, nested sampling `context`/`tools`, elicitation `form`/`url`, `extensions`, and unknown fields. Discovery retains completion and logging capabilities as well. Missing-capability errors carry a `ClientCapabilities` object in `requiredCapabilities`, including the missing sub-capability. Pass `capabilities?` to `on_sampling` or `on_elicitation` to enable sub-capabilities your handler actually supports. Alternatively, call `with_capabilities(ClientCapabilities)` after registering handlers; declaring input support without its handler is rejected. Explicitly omitting a registered handler's capability disables modern input dispatch to that handler.

For URL elicitation, register with `ElicitationCapabilities::new(form=Map([]), url=Map([]))`. Parse raw params with `ElicitationRequest::from_json`: match `Form(message, ..)` or `Url(message, url~, elicitation_id~, ..)`. Results use `ElicitationAction::Accept`, `Decline`, or `Cancel`, and optional flat form content values (`ElicitationValue::String`, `Number`, `Boolean`, or `Strings`). Absent content is omitted, never emitted as null. A form-only handler will not be invoked for URL mode. The SDK passes the URL to your interaction handler; it does not automatically open it or implement OAuth client lifecycle. Sampling handlers can parse raw params with `CreateMessageRequest::from_json` to inspect model preferences, multimodal messages, requested tools, and tool choice. Use `on_sampling(handler, capabilities=SamplingCapabilities::new(tools=Map([])))` only when your handler implements tool-aware sampling. Requests containing `tools` or `toolChoice` are rejected before dispatch without that declaration. Handler results are validated before becoming MRTR input responses. Preserve tool-use IDs when constructing `SamplingContent::Multiple`; your handler, not the SDK, owns model selection, tool execution, and user-consent policies.
