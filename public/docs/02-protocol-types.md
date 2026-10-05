# 2. Protocol Types Reference

All protocol types live in the `colmugx/mcp/protocol/types` package and are re-exported by the root facade `colmugx/mcp`, so application code can use `@mcp.ContentBlock` without a extra import. Import `colmugx/mcp/protocol/types` (alias `@types`) only when you want the explicit path.

Types derive `Debug` and `Eq`. Content blocks, tool definitions/results, resource definitions/templates/read results, and prompt definitions/arguments/messages/results provide shared `ToJson` / `from_json` codecs. Those codecs are strict and lossless: unknown content `type` values are preserved as `Unknown(Json)`, malformed known fields raise `MCPError::InvalidParams`, and non-standard fields survive round-trips through `extensions` maps instead of being dropped. Other types below are undergoing the remaining conformance migration; do not assume that every type already has a lossless codec.

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
let json = @mcp.parse_json(raw_string)
match JsonRpcRequest::from_json(json) {
  Ok(req) => println(req.method_name)
  Err(e) => println(e.message())
}
```

`@mcp.parse_json` preserves numeric literals for exact schema checks and result
round-trips. It raises `MCPError::ParseError` on invalid JSON. Built-in `Json` remains
the wire value type; numbers that were already rounded by another parser or constructed
as a Double cannot recover their original digits. The SDK's tool-call request and
structured-result paths use the preserving parser automatically.

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
  Cancelled(String)                         // local cancellation, not a peer response
  RemoteError(String, code~ : Int, data~ : Json?, extensions~ : Map[String, Json])
  HeaderMismatch(String)                    // -32020 (MCP-defined)
  MissingRequiredClientCapability(          // -32021 (MCP-defined)
    String, required~ : ClientCapabilities,
  )
  UnsupportedProtocolVersion(               // -32022 (MCP-defined)
    String, supported~ : Array[String], requested~ : String,
  )
} derive(Eq, Debug)
```

Methods: `message() -> String`, `to_error_code() -> Int`, and `to_error_data() -> Json?`. Ordinary client error responses become `RemoteError`, retaining the peer's code, data presence (including explicit null), and open fields rather than becoming indistinguishable `InternalError`s. `from_jsonrpc_error` / `to_jsonrpc_error` round-trip those error objects. The current error-code API accepts signed 32-bit integers and rejects out-of-range codes instead of truncating them; full numeric envelope support remains acceptance work.

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
progress_notification(ProgressToken, progress, total?, message?) -> Notification
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
  experimental : Map[String, Json]?
  logging : Map[String, Json]?
  completions : Map[String, Json]?
  tools : ToolCapabilities?
  resources : ResourceCapabilities?
  prompts : PromptCapabilities?
  extensions : Map[String, Json]?
  extra_fields : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct ToolCapabilities {
  list_changed : Bool?
  extra_fields : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct ResourceCapabilities {
  subscribe : Bool?
  list_changed : Bool?
  extra_fields : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct PromptCapabilities {
  list_changed : Bool?
  extra_fields : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct ToolDefinition {
  name : String
  title : String?
  description : String?
  input_schema : Json
  output_schema : Json?
  annotations : ToolAnnotations?
  icons : Array[Icon]?
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Eq, Debug)
```

Use `ToolDefinition::new(name, input_schema, description~, ...)` to avoid filling every optional field. Its codec retains the complete JSON Schema, including `$defs`, references, composition, and `x-mcp-header` annotations. Decoding requires `inputSchema.type` to be `"object"`; preserving a schema is not the same as validating tool execution against it.

`ToolAnnotations` provides optional `title`, `read_only_hint`, `destructive_hint`, `idempotent_hint`, and `open_world_hint`, plus extensions. Omitted hints remain omitted; explicit `false` remains `false`. These are advisory hints, not a basis for authorization or trusting an untrusted server.

### Tool results and shared metadata

```moonbit
pub(all) struct ToolResult {
  content : Array[ContentBlock]
  structured_content : Json?
  is_error : Bool?
  metadata : ResultMetadata
} derive(Eq, Debug)

pub(all) struct ResultMetadata {
  result_type : String?
  ttl_ms : Double?             // nonnegative integral milliseconds
  cache_scope : CacheScope?   // Public / Private
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Eq, Debug)
```

`ToolResult` is owned by `protocol/types` and re-exported through `protocol/tool` and the root facade, so existing `@mcp.ToolResult::text`, `success`, and `error` calls still work. Use `ToolResult::structured(value, content~)` for structured output: objects, arrays, scalars, and explicit JSON null are all supported. `Some(Json::null())` is different from `None`.

The client's `CallToolResult` exposes the same result fields. Check `result.is_error.unwrap_or(false)` for the effective error flag; the optional field preserves the difference between missing and explicit `false`. `result.metadata.server_info()` reads the raw `io.modelcontextprotocol/serverInfo` value without discarding its extensions. `_meta` is kept separate from top-level result extensions, and cache hints retain their wire position. The SDK stores hints here; it does not automatically cache results.

## 2.6 Client types

```moonbit
pub(all) struct ClientInfo {
  name : String
  title : String?
  version : String
} derive(Eq, Debug)

pub(all) struct ClientCapabilities {
  experimental : Map[String, Json]?
  roots : RootCapabilities?
  sampling : SamplingCapabilities?
  elicitation : ElicitationCapabilities?
  extensions : Map[String, Json]?
  extra_fields : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct RootCapabilities {
  list_changed : Bool?
  extra_fields : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct SamplingCapabilities {
  context : Map[String, Json]?
  tools : Map[String, Json]?
  extra_fields : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct ElicitationCapabilities {
  form : Map[String, Json]?
  url : Map[String, Json]?
  extra_fields : Map[String, Json]
} derive(Eq, Debug)
```

All capability types provide `new`, `from_json`, and `to_json`. An absent field differs from an empty object; false notification flags differ from absent flags. `experimental` and `extensions` values must be objects. Unknown fields are retained in `extra_fields`.

Clients start with no input capabilities. Registering `on_roots`, `on_sampling`, or `on_elicitation` enables the corresponding capability; elicitation defaults to form support. MRTR checks the requested elicitation mode and sampling tools sub-capability rather than trusting only the top-level key. Use handler registration's `capabilities?` parameter or `client.with_capabilities` to configure explicit support; declared input capabilities require registered handlers. Servers advertise only registered or explicitly enabled tools/resources/prompts plus an enabled completion registry; use `server.capabilities()` to inspect the discovery view.

## 2.7 Client input types

Modern MCP uses these inputs inside MRTR `inputRequests`, not direct server-to-client JSON-RPC calls. Direct callbacks are used only by the legacy client mode. Sampling codecs preserve model preferences, tools, tool choice, metadata, unknown fields, and the distinction between a single content block and an array:

```moonbit
pub(all) struct Root {
  uri : String
  name : String?
} derive(Eq, Debug)

pub(all) enum SamplingContent {
  Single(SamplingContentBlock)
  Multiple(Array[SamplingContentBlock])
} derive(Eq, Debug)

pub(all) enum SamplingContentBlock {
  Content(ContentBlock)         // text, image, audio
  ToolUse(ToolUseContent)
  ToolResult(ToolResultContent)
  Unknown(Json)
} derive(Eq, Debug)

pub(all) struct SamplingMessage {
  role : Role
  content : SamplingContent
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct CreateMessageRequest {
  messages : Array[SamplingMessage]
  max_tokens : Double          // schema number, not coerced to Int
  model_preferences : ModelPreferences?
  system_prompt : String?
  include_context : SamplingContext?
  temperature : Double?
  stop_sequences : Array[String]?
  metadata : Map[String, Json]?
  tools : Array[ToolDefinition]?
  tool_choice : ToolChoice?
  extensions : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct CreateMessageResult {
  role : Role
  model : String
  content : SamplingContent
  stop_reason : String?
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Eq, Debug)

pub(all) enum ElicitationRequest {
  Form(String, requested_schema~ : Json, explicit_mode~ : Bool,
       meta~ : Map[String, Json]?, extensions~ : Map[String, Json])
  Url(String, url~ : String, elicitation_id~ : String?,
      meta~ : Map[String, Json]?, extensions~ : Map[String, Json])
} derive(Eq, Debug)

pub(all) enum ElicitationAction {
  Accept
  Decline
  Cancel
} derive(Eq, Debug)
pub(all) enum ElicitationValue {
  String(String)
  Number(Double)
  Boolean(Bool)
  Strings(Array[String])
} derive(Eq, Debug)

pub(all) struct ElicitationResult {
  action : ElicitationAction
  content : Map[String, ElicitationValue]?
  extensions : Map[String, Json]
} derive(Eq, Debug)

pub(all) enum ProgressToken {
  String(String)
  Number(Double)
} derive(Eq, Debug)

pub(all) struct ProgressNotification {
  progress_token : ProgressToken
  progress : Double
  total : Double?
  message : String?
  extra_fields : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct CancelledNotification {
  request_id : RequestId
  reason : String?
} derive(Eq, Debug)

pub(all) struct ResourceUpdatedNotification {
  uri : String
} derive(Eq, Debug)
```

For a text response, use `CreateMessageResult::text(model, text, stop_reason?)`; use `new` with `SamplingContent::Multiple` for tool interaction or multimodal output. `ToolUseContent` retains the call ID, name, input object, and metadata. `ToolResultContent` retains the matching `tool_use_id`, complete tool-result content, optional structured JSON (including explicit null), error flag, and metadata. Resource blocks are allowed inside tool-result content, not as top-level sampling blocks.

`ModelPreferences` carries optional hints and cost/speed/intelligence priorities in `[0, 1]`. `SamplingContext` maps `NoContext` / `ThisServer` / `AllServers` to the wire strings. `ToolChoiceMode` maps `Auto` / `Required` / `Disabled` to `auto` / `required` / `none`; an omitted choice mode stays omitted. Register sampling tool support explicitly with `on_sampling(handler, capabilities=SamplingCapabilities::new(tools=Map([])))` before accepting requests containing `tools` or `toolChoice`. The SDK does not execute sampled tool calls or grant model access automatically; your handler owns those policies.

## Resource definitions and read results

`ResourceDefinition` carries `uri`, `name`, optional `title`, `description`, `mime_type`, integral `size`, `icons`, and `metadata: ContentMetadata`. `ResourceTemplateDefinition` has `uri_template` instead of `uri` and no `size`. Their metadata holds annotations, `_meta`, and extensions. Both have `new`, strict `from_json`, and `to_json` codecs.

```moonbit
pub(all) struct ResourceReadResult {
  contents : Array[ResourceContents]
  metadata : ResultMetadata
} derive(Eq, Debug)
```

Use `ResourceReadResult::new(contents, metadata~)`, `text(text, uri~, mime_type?)`, or `blob(base64, uri~, mime_type?)`. This replaces the older single `uri` / `ResourceContent` pair. The client exposes the same contents and result metadata in `ReadResourceResult`; list results also retain result metadata. Resource definitions, templates, contents, and read results are available through the root facade.

## 2.8 Prompt types

```moonbit
pub(all) struct PromptDefinition {
  name : String
  title : String?
  description : String?
  arguments : Array[PromptArgument]?
  icons : Array[Icon]?
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct PromptArgument {
  name : String
  title : String?
  description : String?
  required : Bool?
  extensions : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct PromptMessage {
  role : String         // codec accepts "user" or "assistant"
  content : ContentBlock
  extensions : Map[String, Json]
} derive(Eq, Debug)

pub(all) struct GetPromptResult {
  description : String?
  messages : Array[PromptMessage]
  metadata : ResultMetadata
} derive(Eq, Debug)
```

All four types have shared `from_json` / `to_json` codecs and are re-exported by the facade. Use `PromptDefinition::new`, `PromptArgument::new`, `PromptMessage::new(Role::User, content)`, and `GetPromptResult::new(messages)` to start from empty optional metadata. `required=false`, empty arguments, absent arguments, and unknown message/result fields remain distinct. Standard prompt definitions have no `annotations` field; vendor annotations can be preserved explicitly in `extensions`.
