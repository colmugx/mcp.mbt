# 2. Protocol Types Reference

All protocol types live in the `colmugx/mcp/protocol/types` package and are re-exported by the root facade `colmugx/mcp`, so application code can use `@mcp.ContentBlock` without a extra import. Import `colmugx/mcp/protocol/types` (alias `@types`) only when you want the explicit path.

Types derive `Debug` and `Eq`; serialization is provided by `ToJson` impls and `from_json` codecs. Decoding is strict and lossless: unknown `type` values are preserved as `Unknown(Json)`, known types with missing required fields raise `MCPError::InvalidParams`, and non-standard fields survive round-trips through `extensions` maps instead of being dropped.

## 2.1 JSON-RPC envelope

### RequestId

```moonbit
pub(all) enum RequestId {
  Int(Int)     // numeric id
  Str(String)  // string id
} derive(Eq, Debug)
```

`RequestId::to_json_string` renders either form as JSON text (string ids are quoted and escaped by the JSON serializer).

### JsonRpcRequest

```moonbit
pub(all) struct JsonRpcRequest {
  jsonrpc : String      // always "2.0"
  id : RequestId        // request id (Int or Str)
  method_name : String  // e.g. "tools/list"
  params : Json         // params object
} derive(Eq, Debug)
```

Parse from JSON:

```moonbit
let json = @json.parse(raw_string)
match JsonRpcRequest::from_json(json) {
  Ok(req) => println(req.method_name)
  Err(e) => println(e.message())
}
```

## 2.2 Errors

### MCPError — protocol-level errors

```moonbit
pub(all) suberror MCPError {
  ParseError(String)                        // -32700
  InvalidRequest(String)                    // -32600
  MethodNotFound(String)                    // -32601
  InvalidParams(String)                     // -32602; also resource-not-found
  InternalError(String)                     // -32603
  TransportError(TransportError)            // wrapped transport failure
  ToolError(String)                         // -32000 (implementation-defined)
  HeaderMismatch(String)                    // -32020 (MCP-defined)
  MissingRequiredClientCapability(          // -32021 (MCP-defined)
    String, required~ : Array[String],
  )
  UnsupportedProtocolVersion(               // -32022 (MCP-defined)
    String, supported~ : Array[String], requested~ : String,
  )
} derive(Eq, Debug)
```

Methods: `message() -> String`, `to_error_code() -> Int`, and `to_error_data() -> Json?` (populates the recovery `data` field for the `-3202x` MCP-defined errors, e.g. the server's supported versions).

### TransportError — transport-level errors

```moonbit
pub(all) suberror TransportError {
  ConnectionClosed         // clean shutdown
  ReadError(String)        // read failure
  WriteError(String)       // write failure
  Timeout                  // operation timed out
  InvalidState(String)     // e.g. send after close
  Unauthorized(String)     // HTTP 401, carries WWW-Authenticate info
  Forbidden(String)        // HTTP 403, insufficient scope
  HttpError(Int, String)   // other HTTP status + response body
} derive(Eq, Debug)
```

`HttpError` exists so callers (such as the era probe) can inspect the body for a recognized JSON-RPC error before deciding how to proceed.

### ToolError — tool argument decoding

```moonbit
pub suberror ToolError {
  ToolError(String)
}
```

Raised by generated `Params::from_json` implementations when tool arguments do not match the declared schema.

## 2.3 ContentBlock

Content is the one model shared by tools, prompts, and sampling:

```moonbit
pub(all) enum ContentBlock {
  Text(String, metadata~ : ContentMetadata)
  Image(String, mime_type~ : String, metadata~ : ContentMetadata)
  Audio(String, mime_type~ : String, metadata~ : ContentMetadata)
  ResourceLink(ResourceLinkData, metadata~ : ContentMetadata)
  EmbeddedResource(ResourceContents, metadata~ : ContentMetadata)
  /// A future content type, retained without interpreting its fields.
  Unknown(Json)
} derive(Eq, Debug)
```

`ContentBlock` replaces the older `ContentItem` type. Builders set metadata to empty by default; pass `metadata~` when you need annotations or `_meta`:

```moonbit
let text = @mcp.ContentBlock::text("hello")
let audio = @mcp.ContentBlock::audio("aGk=", mime_type="audio/wav")
let link = @mcp.ContentBlock::resource_link("memo://1", name="memo")
let embedded = @mcp.ContentBlock::resource(
  @mcp.ResourceContents::blob("aGk=", uri="memo://2"),
)
```

### ContentMetadata

```moonbit
pub(all) struct ContentMetadata {
  annotations : Annotations?
  meta : Map[String, Json]?      // the wire `_meta` object
  extensions : Map[String, Json] // non-standard fields, preserved verbatim
} derive(Eq, Debug)
```

An empty `annotations`/`_meta` object and an absent one are different states and stay distinct through a round-trip.

### Annotations

```moonbit
pub(all) struct Annotations {
  audience : Array[Role]?      // Role::User / Role::Assistant
  priority : Double?           // 0.0 ..= 1.0, validated on decode
  last_modified : String?
  extensions : Map[String, Json]
} derive(Eq, Debug)
```

### ResourceLinkData and Icon

`ResourceLinkData` carries `uri`, required `name`, optional `title`, `description`, `mime_type`, `size` (integral), and `icons`. `Icon` carries `src`, optional `mime_type`, `sizes`, `theme` (`IconTheme::Light` / `IconTheme::Dark`), and extensions. The SDK stores icon descriptions only; it never fetches or renders icons.

### ResourceContents

```moonbit
pub(all) enum ResourceData {
  Text(String)
  Blob(String)
} derive(Eq, Debug)

pub(all) struct ResourceContents {
  uri : String
  mime_type : String?
  data : ResourceData
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Eq, Debug)
```

`ResourceContents` replaces the older `EmbeddedResourceContent`. MIME type is optional for both text and blob; the embedded wire shape stays `{ "type": "resource", "resource": { "uri", "text" | "blob", "mimeType?", "_meta?" } }`, with inner and outer metadata kept separate. When a payload carries both `text` and `blob` (the wire union permits it), the decoder prefers `text` and keeps the other field in `extensions`.

When pattern matching, `Text(text, ..)` ignores metadata; use `Text(text, metadata~)` when you need it.

## 2.4 Notifications

```moonbit
pub(all) struct Notification {
  method_name : String  // e.g. "notifications/tools/list_changed"
  params : Json?
} derive(Eq, Debug)
```

Factory helpers:

```moonbit
tools_list_changed_notification()                 -> Notification
resources_list_changed_notification()             -> Notification
prompts_list_changed_notification()               -> Notification
resources_updated_notification(uri : String)      -> Notification
progress_notification(token, progress, total?)    -> Notification
cancelled_notification(request_id, reason?)       -> Notification
```

## 2.5 Server types

```moonbit
pub(all) struct ServerInfo {
  name : String
  title : String?
  version : String
  description : String?
} derive(Eq, Debug)

pub(all) struct ServerCapabilities {
  tools : ToolCapabilities?
  resources : ResourceCapabilities?
  prompts : PromptCapabilities?
  extensions : Map[String, Json]?
} derive(Eq, Debug)

pub(all) struct ToolCapabilities {
  list_changed : Bool
} derive(Eq, Debug)

pub(all) struct ResourceCapabilities {
  subscribe : Bool
  list_changed : Bool
} derive(Eq, Debug)

pub(all) struct PromptCapabilities {
  list_changed : Bool
} derive(Eq, Debug)

pub(all) struct ToolDefinition {
  name : String
  description : String
  input_schema : Json
} derive(Eq, Debug)
```

## 2.6 Client types

```moonbit
pub(all) struct ClientInfo {
  name : String
  title : String?
  version : String
} derive(Eq, Debug)

pub(all) struct ClientCapabilities {
  roots : RootCapabilities?
  sampling : SamplingCapabilities?
  elicitation : ElicitationCapabilities?
  extensions : Map[String, Json]?
} derive(Eq, Debug)

pub(all) struct RootCapabilities {
  list_changed : Bool
} derive(Eq, Debug)

/// Marker: the client can answer sampling/createMessage.
pub(all) struct SamplingCapabilities {} derive(Eq, Debug)

pub(all) struct ElicitationCapabilities {
  form : Bool
} derive(Eq, Debug)
```

`default_capabilities()` enables roots, sampling, and elicitation. Pass your own `ClientCapabilities` to the connect helpers to advertise less.

## 2.7 Bidirectional types

These cover server-to-client requests (sampling, roots, elicitation) and their notifications:

```moonbit
pub(all) struct Root {
  uri : String
  name : String?
} derive(Eq, Debug)

pub(all) struct SamplingMessage {
  role : String          // "user" or "assistant"
  content : ContentBlock
} derive(Eq, Debug)

pub(all) struct CreateMessageRequest {
  messages : Array[SamplingMessage]
  max_tokens : Int
  system_prompt : String?
  include_context : String?
  temperature : Double?
  stop_sequences : Array[String]?
  metadata : Json?
} derive(Eq, Debug)

pub(all) struct CreateMessageResult {
  role : String
  model : String
  content : ContentBlock
  stop_reason : String?
} derive(Eq, Debug)

pub(all) struct ElicitationRequest {
  message : String
  requested_schema : Json
} derive(Eq, Debug)

pub(all) struct ElicitationResult {
  action : String    // "accept", "decline", or "cancel"
  content : Json?
} derive(Eq, Debug)

pub(all) struct ProgressNotification {
  progress_token : String
  progress : Double
  total : Double?
  message : String?
} derive(Eq, Debug)

pub(all) struct CancelledNotification {
  request_id : RequestId
  reason : String?
} derive(Eq, Debug)

pub(all) struct ResourceUpdatedNotification {
  uri : String
} derive(Eq, Debug)
```

## 2.8 Prompt types

```moonbit
pub(all) struct PromptArgument {
  name : String
  description : String?
  required : Bool?
} derive(Eq, Debug)

pub(all) struct PromptMessage {
  role : String         // "user" or "assistant"
  content : ContentBlock
} derive(Eq, Debug)

pub(all) struct GetPromptResult {
  description : String?
  messages : Array[PromptMessage]
} derive(Eq, Debug)
```
