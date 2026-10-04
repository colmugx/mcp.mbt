///|
pub using @types {
  type ResourceDefinition,
  type ResourceTemplateDefinition,
  type ResourceReadResult,
  type ResourceContents,
  type ResourceData,
}

///|
/// A resource read completes with multiple contents or suspends for client input.
pub(all) enum ResourceReadOutcome {
  Complete(ResourceReadResult)
  InputRequired(
    input_requests~ : Map[String, @types.InputRequestEntry],
    state~ : Json
  )
} derive(Eq, Debug)

///|
pub(open) trait Resource {
  fn name(Self) -> String
  fn description(Self) -> String
  fn uri(Self) -> String
  fn mime_type(Self) -> String
  async fn read(Self, @runtime.RequestContext) -> Result[
    ResourceReadResult,
    @types.MCPError,
  ]
}

///|
pub(open) trait ResourceMRTR {
  fn name(Self) -> String
  fn description(Self) -> String
  fn uri(Self) -> String
  fn mime_type(Self) -> String
  async fn read(Self, @runtime.RequestContext, Json) -> Result[
    ResourceReadOutcome,
    @types.MCPError,
  ]
}

///|
pub extend ResourceReadOutcome with Eq::{not_equal, equal}

///|
pub extend ResourceReadOutcome with @moonbitlang/core/debug.Debug::{to_repr}
