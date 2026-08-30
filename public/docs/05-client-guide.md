# Client Guide

## Connect

Use high-level connection helpers. They create the transport and run `initialize` before returning.

```moonbit
let client = @mcp.MCPClient::connect_http(
  url="http://localhost:4240/mcp",
  name="client",
  version="1.0.0",
)
```

STDIO connections need a task group because the child process lifecycle belongs to async supervision:

```moonbit
@async.with_task_group(group => {
  let client = @mcp.MCPClient::connect_stdio(
    cmd="moon",
    args=["run", "server"],
    name="client",
    version="1.0.0",
    group~,
  )
})
```

## Calls

The main client methods are:

- `initialize`
- `list_tools`
- `call_tool`
- `list_resources`
- `read_resource`
- `list_prompts`
- `get_prompt`
- `complete`
- `close`

```moonbit
match client.call_tool("echo", arguments="{\"text\":\"hello\"}") {
  Ok(result) => ignore(result)
  Err(e) => println(e.message())
}
```

## Runtime

The client runtime owns:

- request id generation
- pending response queues keyed by JSON-RPC id
- response dispatch
- server notification dispatch
- server-to-client requests such as `sampling/createMessage`, `roots/list`, and `elicitation/create`

Notifications do not wake pending requests. Out-of-order responses are routed by id.

## Bidirectional Mode

Register handlers and run the event loop in a task group:

```moonbit
let client = client
  .on_sampling(fn(params) { Ok(result) })
  .on_roots(fn() { Ok([]) })
  .on_elicitation(fn(params) { Ok(result) })

@async.with_task_group(group => {
  group.spawn_bg(fn() { client.run(group) })
})
```

Use `on_notification` for server notifications.
