///| Prompt Core Types - MCP Protocol Implementation

///| Based on: MCP Protocol 2026-07-28 specification

///|
/// Prompt metadata definition (for protocol responses)
/// Describes a prompt in the prompts/list response
/// Note: This is separate from the Prompt trait which is for implementation
/// Note: PromptArgument, PromptMessage, GetPromptResult are defined in @types package
pub(all) struct PromptDefinition {
  name : String
  description : String?
  arguments : Array[@types.PromptArgument]?
} derive(Eq, Debug)

///|
/// The result of a `prompts/get` handler. Per the 2026-07-28 MRTR pattern, a
/// handler may either complete normally (`Complete`) or request additional
/// client input (`InputRequired`). On retry, the client resubmits with
/// `inputResponses` and the echoed `requestState`; the handler receives those
/// responses via `_mrtr_responses` in the get params.
pub(all) enum PromptGetOutcome {
  /// Normal completion — the prompt messages are ready.
  Complete(@types.GetPromptResult)
  /// The handler needs client input before it can finish. `input_requests`
  /// maps server-assigned keys to elicitation/sampling/roots requests;
  /// `state` is opaque server continuation data sealed into `requestState`.
  InputRequired(
    input_requests~ : Map[String, @types.InputRequestEntry],
    state~ : Json
  )
} derive(Eq, Debug)

///|
/// Core Prompt trait following MCP protocol
/// - name: Prompt identifier (unique)
/// - description: Human-readable description
/// - arguments: Array of argument definitions (@types.PromptArgument)
/// - get: Async operation that returns prompt messages based on provided arguments
pub(open) trait Prompt {
  fn name(Self) -> String
  fn description(Self) -> String
  fn arguments(Self) -> Array[@types.PromptArgument]

  /// Get prompt messages with provided arguments
  /// Returns GetPromptResult with messages
  async fn get(Self, Json) -> Result[@types.GetPromptResult, @types.MCPError]
}

///|
/// MRTR-aware prompt trait. Implement this instead of `Prompt` when a
/// `prompts/get` handler needs to suspend and ask the client for input before
/// completing. The `get` method receives the full get params (after
/// `_mrtr_responses` has been merged on retry).
pub(open) trait PromptMRTR {
  fn name(Self) -> String
  fn description(Self) -> String
  fn arguments(Self) -> Array[@types.PromptArgument]

  /// Get prompt messages with the full request params.
  /// Returns `Complete` for a normal result, or `InputRequired` to trigger an
  /// MRTR round-trip.
  async fn get(Self, Json) -> Result[PromptGetOutcome, @types.MCPError]
}
