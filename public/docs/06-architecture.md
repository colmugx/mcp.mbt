# Architecture

v0.14 separates the SDK into four layers.

## Protocol

Protocol packages define JSON-RPC and MCP data types. They are pure data and serialization code, with no async runtime ownership.

## Runtime

Runtime code owns concurrency semantics.

`ServerRuntime` responsibilities:

- parse request once
- classify fast and slow methods
- dispatch server handlers
- serialize STDIO output
- preserve HTTP per-request reply queues

`ClientRuntime` responsibilities:

- allocate request IDs
- store pending response queues
- dispatch responses by JSON-RPC id
- dispatch notifications
- answer server-to-client requests

`HostRuntime` responsibilities:

- own multiple named clients
- aggregate tool lists
- route `connection.tool` calls
- close all connections

## Transport

Transport implementations perform concrete I/O: server STDIO, server HTTP, client STDIO, and client HTTP. They are advanced extension points, not the ordinary application API.

## Application API

Most users should only need:

- `MCPServer`
- `MCPClient`
- `MCPHost`

Host is layered above client. It is not a replacement for client internals; it is a coordinator for multiple client connections.

## Performance Notes

Fast server methods avoid spawning. Slow methods spawn only when handler execution can suspend. HTTP uses request-local reply queues, while STDIO uses a single output queue to avoid interleaved writes.
