///| Resource Core Types - MCP Protocol Implementation

///| Based on: MCP Protocol 2025-06-18 specification

///|=====================================================

///| Resource Content Types

///|=====================================================

///|
/// Content type for MCP resource read results
/// Supports text and binary blob content types per MCP spec
pub(all) enum ResourceContent {
  Text(String)
  /// Binary blob with base64 data and mime type
  Blob(String, mime_type~ : String)
} derive(Eq, Show)

///|=====================================================

///| Resource Definition (metadata only, not used for trait implementation)

///|=====================================================

///|
/// Resource metadata definition (for protocol responses)
/// Describes a resource in the resources/list response
/// Note: This is separate from the Resource trait which is for implementation
pub(all) struct ResourceDefinition {
  uri : String
  name : String
  description : String?
  mime_type : String?
} derive(Eq, Show)

///|=====================================================

///| Resource Read Result

///|=====================================================

///|
/// Result of reading a resource
/// Contains the URI and content of the resource
pub(all) struct ResourceReadResult {
  uri : String
  content : ResourceContent
} derive(Eq, Show)

///|=====================================================

///| Resource Trait (Main API)

///|=====================================================

///|
/// Core Resource trait following MCP protocol
/// - name: Resource identifier (unique)
/// - description: Human-readable description
/// - uri: Resource URI (e.g., "file:///path/to/file")
/// - mime_type: MIME type of the resource content
/// - read: Async read operation returning resource content
pub(open) trait Resource {
  name(Self) -> String
  description(Self) -> String
  uri(Self) -> String
  mime_type(Self) -> String

  /// Read resource content (async)
  /// Returns ResourceReadResult with content
  async read(Self) -> Result[ResourceReadResult, @types.MCPError]
}
