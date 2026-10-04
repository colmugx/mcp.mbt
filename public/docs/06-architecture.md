# 6. Architecture

The SDK separates into four layers. Each layer only depends on the ones above it.

## Protocol

`protocol/types` owns wire models and codecs: pure data and serialization, without transport I/O. The tool/resource/prompt/core packages re-export those models and define handler traits/helpers. Those handler APIs depend on the public `runtime` package's `RequestContext`, but do not own transport tasks. Pure wire codecs are tested on native and js; platform I/O follows the transport target gates.

## Runtime

Runtime code owns concurrency semantics.

`MCPServer` owns server runtime responsibilities:

- parse each request once
- classify fast and slow methods
- dispatch server handlers
- serialize stdio output
- preserve HTTP per-request reply queues and trusted principals
- restore and bind stateless MRTR continuation state
- cancel scoped in-flight tasks and suppress late responses/progress

The public `runtime` package supplies `RequestContext`, `Principal`, `CancellationToken`, and `ProgressReporter`; it does not hide an additional `ServerRuntime` object that applications must construct.

`MCPClient` owns client runtime responsibilities:

- allocate request IDs
- store pending response queues
- dispatch responses by JSON-RPC id
- dispatch notifications
- fulfill MRTR input requests in modern mode; answer server-to-client requests only in legacy mode

`MCPHost` owns host responsibilities:

- own multiple named clients
- aggregate tool lists under `connection.tool` names
- route `connection.tool` calls
- close all connections

## Transport

Transport implementations perform concrete I/O: server stdio, server HTTP, client stdio, and client HTTP. They are advanced extension points, not the ordinary application API — see the [transport reference](04-transport-reference.md) for the target support matrix.

## Application API

Most applications need only three types, all re-exported by the root facade `colmugx/mcp`:

- `MCPServer`
- `MCPClient`
- `MCPHost`

Host sits above client. It is not a replacement for client internals; it is a coordinator for multiple client connections.

## Performance notes

Fast server methods avoid spawning. Slow methods spawn only when the handler can suspend. HTTP uses request-local reply queues, while stdio uses a single output queue to avoid interleaved writes.
