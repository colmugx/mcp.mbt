# 6. Architecture

The SDK separates into four layers. Each layer only depends on the ones above it.

## Protocol

Protocol packages (`protocol/types`, `protocol/tool`, `protocol/resource`, `protocol/prompt`, `protocol/core`) define JSON-RPC and MCP data types plus codecs. They are pure data and serialization code with no async-runtime ownership, so they compile and test identically on every target.

## Runtime

Runtime code owns concurrency semantics.

`ServerRuntime` responsibilities:

- parse each request once
- classify fast and slow methods
- dispatch server handlers
- serialize stdio output
- preserve HTTP per-request reply queues

`ClientRuntime` responsibilities:

- allocate request IDs
- store pending response queues
- dispatch responses by JSON-RPC id
- dispatch notifications
- answer server-to-client requests

`HostRuntime` responsibilities:

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
