///| Resource Core Types - MCP Protocol Implementation

///| Based on: MCP Protocol 2026-07-28 specification

///|
/// Content type for MCP resource read results
/// Supports text and binary blob content types per MCP spec
pub(all) enum ResourceContent {
  Text(String)
  /// Binary blob with base64 data and mime type
  Blob(String, mime_type~ : String)
} derive(Eq, Debug)

///|
/// Resource metadata definition (for protocol responses)
/// Describes a resource in the resources/list response
/// Note: This is separate from the Resource trait which is for implementation
pub(all) struct ResourceDefinition {
  uri : String
  name : String
  description : String?
  mime_type : String?
} derive(Eq, Debug)

///|
/// Result of reading a resource
/// Contains the URI and content of the resource
pub(all) struct ResourceReadResult {
  uri : String
  content : ResourceContent
} derive(Eq, Debug)

///|
/// The result of a `resources/read` handler. Per the 2026-07-28 MRTR pattern,
/// a handler may either complete normally (`Complete`) or request additional
/// client input (`InputRequired`). On retry, the client resubmits with
/// `inputResponses` and the echoed `requestState`; the handler receives those
/// responses via `_mrtr_responses` in the read params.
pub(all) enum ResourceReadOutcome {
  /// Normal completion — the resource content is ready.
  Complete(ResourceReadResult)
  /// The handler needs client input before it can finish. `input_requests`
  /// maps server-assigned keys to elicitation/sampling/roots requests;
  /// `state` is opaque server continuation data sealed into `requestState`.
  InputRequired(
    input_requests~ : Map[String, @types.InputRequestEntry],
    state~ : Json
  )
} derive(Eq, Debug)

///|
/// Metadata for a resource template returned by `resources/templates/list`.
pub(all) struct ResourceTemplateDefinition {
  uri_template : String
  name : String
  description : String?
  mime_type : String?
} derive(Eq, Debug)

///|
/// Core Resource trait following MCP protocol
/// - name: Resource identifier (unique)
/// - description: Human-readable description
/// - uri: Resource URI (e.g., "file:///path/to/file")
/// - mime_type: MIME type of the resource content
/// - read: Async read operation returning resource content
pub(open) trait Resource {
  fn name(Self) -> String
  fn description(Self) -> String
  fn uri(Self) -> String
  fn mime_type(Self) -> String

  /// Read resource content (async)
  /// Returns ResourceReadResult with content
  async fn read(Self) -> Result[ResourceReadResult, @types.MCPError]
}

///|
/// MRTR-aware resource trait. Implement this instead of `Resource` when a
/// `resources/read` handler needs to suspend and ask the client for input
/// before completing. The `read` method receives the full read params (after
/// `_mrtr_responses` has been merged on retry).
pub(open) trait ResourceMRTR {
  fn name(Self) -> String
  fn description(Self) -> String
  fn uri(Self) -> String
  fn mime_type(Self) -> String

  /// Read resource content with the full request params.
  /// Returns `Complete` for a normal result, or `InputRequired` to trigger an
  /// MRTR round-trip.
  async fn read(Self, Json) -> Result[ResourceReadOutcome, @types.MCPError]
}
