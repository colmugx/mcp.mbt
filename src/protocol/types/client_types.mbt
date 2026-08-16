///|
/// Client Info — sent during initialization
pub(all) struct ClientInfo {
  name : String
  title : String?
  version : String
} derive(Debug, Eq)

///|
/// Client Capabilities — declared during initialization
pub(all) struct ClientCapabilities {
  roots : RootCapabilities?
  sampling : SamplingCapabilities?
  elicitation : ElicitationCapabilities?
  /// Optional protocol extensions, per 2026-07-28 versioning: a map of
  /// extension identifiers (following `_meta` key naming rules) to
  /// per-extension settings objects.
  extensions : Map[String, Json]?
} derive(Debug, Eq)

///|
/// Root Capabilities — client can provide filesystem roots
pub(all) struct RootCapabilities {
  list_changed : Bool
} derive(Debug, Eq)

///|
/// Sampling Capabilities — client supports LLM sampling requests
pub(all) struct SamplingCapabilities {} derive(Debug, Eq)

///|
/// Elicitation Capabilities — client supports user interaction requests
pub(all) struct ElicitationCapabilities {
  form : Bool
} derive(Debug, Eq)

///|
/// Root — a filesystem root exposed by the client for `roots/list`
pub(all) struct Root {
  uri : String
  name : String?
} derive(Debug, Eq)

///|
/// SamplingMessage — a message within a sampling/createMessage request
pub(all) struct SamplingMessage {
  role : String
  content : ContentItem
} derive(Debug, Eq)

///|
/// CreateMessageRequest — server asks client to sample an LLM
pub(all) struct CreateMessageRequest {
  messages : Array[SamplingMessage]
  max_tokens : Int
  system_prompt : String?
  include_context : String?
  temperature : Double?
  stop_sequences : Array[String]?
  metadata : Json?
} derive(Debug, Eq)

///|
/// CreateMessageResult — client's response to a sampling request
pub(all) struct CreateMessageResult {
  role : String
  model : String
  content : ContentItem
  stop_reason : String?
} derive(Debug, Eq)

///|
/// ElicitationRequest — server asks client to interact with the user
pub(all) struct ElicitationRequest {
  message : String
  requested_schema : Json
} derive(Debug, Eq)

///|
/// ElicitationResult — client's response to an elicitation request
pub(all) struct ElicitationResult {
  action : String
  content : Json?
} derive(Debug, Eq)

///|
/// ProgressNotification — params for `notifications/progress`
pub(all) struct ProgressNotification {
  progress_token : String
  progress : Double
  total : Double?
  message : String?
} derive(Debug, Eq)

///|
/// CancelledNotification — params for `notifications/cancelled`
pub(all) struct CancelledNotification {
  request_id : RequestId
  reason : String?
} derive(Debug, Eq)

///|
/// ResourceUpdatedNotification — params for `notifications/resources/updated`
pub(all) struct ResourceUpdatedNotification {
  uri : String
} derive(Debug, Eq)
