///|
/// Client Info — sent during initialization
pub(all) struct ClientInfo {
  name : String
  title : String?
  version : String
} derive(Show, Eq)

///|
/// Client Capabilities — declared during initialization
pub(all) struct ClientCapabilities {
  roots : RootCapabilities?
  sampling : Bool
  elicitation : Bool
} derive(Show, Eq)

///|
/// Root Capabilities — client can provide filesystem roots
pub(all) struct RootCapabilities {
  list_changed : Bool
} derive(Show, Eq)
