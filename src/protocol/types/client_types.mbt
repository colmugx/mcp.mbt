///|
/// Client Info — sent during initialization
#derive(Debug, Eq)
pub(all) struct ClientInfo {
  name : String
  title : String?
  version : String
}

///|
/// Client Capabilities — declared during initialization
#derive(Debug, Eq)
pub(all) struct ClientCapabilities {
  experimental : Map[String, Json]?
  roots : RootCapabilities?
  sampling : SamplingCapabilities?
  elicitation : ElicitationCapabilities?
  extra_fields : Map[String, Json]
  /// Optional protocol extensions, per 2026-07-28 versioning: a map of
  /// extension identifiers (following `_meta` key naming rules) to
  /// per-extension settings objects.
  extensions : Map[String, Json]?
}

///|
/// Root Capabilities — client can provide filesystem roots
#derive(Debug, Eq)
pub(all) struct RootCapabilities {
  list_changed : Bool?
  extra_fields : Map[String, Json]
}

///|
/// Sampling Capabilities — client supports LLM sampling requests
#derive(Debug, Eq)
pub(all) struct SamplingCapabilities {
  context : Map[String, Json]?
  tools : Map[String, Json]?
  extra_fields : Map[String, Json]
}

///|
/// Elicitation Capabilities — client supports user interaction requests
#derive(Debug, Eq)
pub(all) struct ElicitationCapabilities {
  form : Map[String, Json]?
  url : Map[String, Json]?
  extra_fields : Map[String, Json]
}

///|
/// Root — a filesystem root exposed by the client for `roots/list`
#derive(Debug, Eq)
pub(all) struct Root {
  uri : String
  name : String?
}

///|
/// SamplingMessage — a message within a sampling/createMessage request
#derive(Debug, Eq)
pub(all) struct SamplingMessage {
  role : Role
  content : SamplingContent
  meta : Map[String, Json]?
  extensions : Map[String, Json]
}

///|
/// CreateMessageRequest — server asks client to sample an LLM.
/// `max_tokens` keeps the exact integer literal (pinned schema: `integer`);
/// `temperature` keeps the exact decimal literal (pinned schema: `number`).
#derive(Debug, Eq)
pub(all) struct CreateMessageRequest {
  messages : Array[SamplingMessage]
  max_tokens : JsonInteger
  model_preferences : ModelPreferences?
  system_prompt : String?
  include_context : SamplingContext?
  temperature : JsonNumber?
  stop_sequences : Array[String]?
  metadata : Map[String, Json]?
  tools : Array[ToolDefinition]?
  tool_choice : ToolChoice?
  extensions : Map[String, Json]
}

///|
/// CreateMessageResult — client's response to a sampling request
#derive(Debug, Eq)
pub(all) struct CreateMessageResult {
  role : Role
  model : String
  content : SamplingContent
  stop_reason : String?
  meta : Map[String, Json]?
  extensions : Map[String, Json]
}

///|
/// ElicitationRequest — server asks client to interact with the user
#derive(Debug, Eq)
pub(all) enum ElicitationRequest {
  Form(
    String,
    requested_schema~ : Json,
    explicit_mode~ : Bool,
    meta~ : Map[String, Json]?,
    extensions~ : Map[String, Json]
  )
  Url(
    String,
    url~ : String,
    elicitation_id~ : String?,
    meta~ : Map[String, Json]?,
    extensions~ : Map[String, Json]
  )
}

///|
/// ElicitationResult — client's response to an elicitation request
#derive(Debug, Eq)
pub(all) struct ElicitationResult {
  action : ElicitationAction
  content : Map[String, ElicitationValue]?
  extensions : Map[String, Json]
}

///|
/// ProgressNotification — params for `notifications/progress`.
/// Counters keep exact decimal literals (pinned schema: `number`).
#derive(Debug, Eq)
pub(all) struct ProgressNotification {
  progress_token : ProgressToken
  progress : JsonNumber
  total : JsonNumber?
  message : String?
  extra_fields : Map[String, Json]
}

///|
/// CancelledNotification — params for `notifications/cancelled`
#derive(Debug, Eq)
pub(all) struct CancelledNotification {
  request_id : RequestId
  reason : String?
}

///|
/// ResourceUpdatedNotification — params for `notifications/resources/updated`
#derive(Debug, Eq)
pub(all) struct ResourceUpdatedNotification {
  uri : String
}

///|
/// Explicit trait method promotion for current MoonBit toolchains.
pub extend ClientInfo with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ClientInfo with Eq::{not_equal, equal}

///|
pub extend ClientCapabilities with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ClientCapabilities with Eq::{not_equal, equal}

///|
pub extend RootCapabilities with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RootCapabilities with Eq::{not_equal, equal}

///|
pub extend SamplingCapabilities with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SamplingCapabilities with Eq::{not_equal, equal}

///|
pub extend ElicitationCapabilities with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ElicitationCapabilities with Eq::{not_equal, equal}

///|
pub extend Root with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Root with Eq::{not_equal, equal}

///|
pub extend SamplingMessage with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SamplingMessage with Eq::{not_equal, equal}

///|
pub extend CreateMessageRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CreateMessageRequest with Eq::{not_equal, equal}

///|
pub extend CreateMessageResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CreateMessageResult with Eq::{not_equal, equal}

///|
pub extend ElicitationRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ElicitationRequest with Eq::{not_equal, equal}

///|
pub extend ElicitationResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ElicitationResult with Eq::{not_equal, equal}

///|
pub extend ProgressNotification with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProgressNotification with Eq::{not_equal, equal}

///|
pub extend CancelledNotification with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CancelledNotification with Eq::{not_equal, equal}

///|
pub extend ResourceUpdatedNotification with @moonbitlang/core/debug.Debug::{
  to_repr,
}

///|
pub extend ResourceUpdatedNotification with Eq::{not_equal, equal}
