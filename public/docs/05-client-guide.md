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

- `list_tools(cursor?)` / `call_tool(name, arguments?)`
- `list_resources(cursor?)` / `read_resource(uri)` / `list_resource_templates(cursor?)`
- `list_prompts(cursor?)` / `get_prompt(name, arguments?)`
- `complete(ref_type~, ref_name~, argument_name~, argument_value~)`
- `discover()` — re-fetch server capabilities
- `cancel_request(request_id, reason?)` — cancel an in-flight request
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

`arguments` is the JSON-encoded arguments object. `read_resource` returns `ReadResourceResult` with a `contents` array; each entry carries a `uri` and text or blob `content`.

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

For multiplexed subscriptions on one long-lived request, use `listen(filter?, handler~, group~)`; it returns a subscription id you can pass to `cancel_listen`.

## Bidirectional mode

Servers may call back into the client for sampling, roots, and elicitation. Register handlers, then run the event loop:

```moonbit
let client = client
  .on_sampling(fn(params) {
    Ok({ role: "assistant", model: "m", content: @mcp.ContentBlock::text("hi"), stop_reason: None })
  })
  .on_roots(fn() { Ok([]) })
  .on_elicitation(fn(_params) {
    Ok({ action: "cancel", content: None })
  })

@async.with_task_group(group => {
  group.spawn_bg(() => { client.run(group) })
})
```

Handler signatures: `on_sampling((Json) -> Result[CreateMessageResult, MCPError])`, `on_roots(() -> Result[Array[Root], MCPError])`, `on_elicitation((Json) -> Result[ElicitationResult, MCPError])`. A capability without a registered handler is answered with `-32601`, which fails the server's original request — advertise only what you can serve (pass explicit `ClientCapabilities` instead of the all-on defaults when unsure).
