///| Prompt Core Types - MCP Protocol Implementation

///| Based on: MCP Protocol 2025-06-18 specification

///|=====================================================

///| Prompt Definition (metadata only, not used for trait implementation)

///|=====================================================

///|
/// Prompt metadata definition (for protocol responses)
/// Describes a prompt in the prompts/list response
/// Note: This is separate from the Prompt trait which is for implementation
/// Note: PromptArgument, PromptMessage, GetPromptResult are defined in @types package
pub(all) struct PromptDefinition {
  name : String
  description : String?
  arguments : Array[@types.PromptArgument]?
} derive(Eq, Show)

///|=====================================================

///| Prompt Trait (Main API)

///|=====================================================

///|
/// Core Prompt trait following MCP protocol
/// - name: Prompt identifier (unique)
/// - description: Human-readable description
/// - arguments: Array of argument definitions (@types.PromptArgument)
/// - get: Async operation that returns prompt messages based on provided arguments
pub(open) trait Prompt {
  name(Self) -> String
  description(Self) -> String
  arguments(Self) -> Array[@types.PromptArgument]

  /// Get prompt messages with provided arguments
  /// Returns GetPromptResult with messages
  async get(Self, Json) -> Result[@types.GetPromptResult, @types.MCPError]
}
