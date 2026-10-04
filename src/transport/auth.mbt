///|
/// Server-side Bearer authentication. The hook must validate credentials and scopes
/// and return a stable identity; request metadata is never an identity source.
pub struct AuthConfig {
  authenticate : (String) -> @runtime.Principal?
  resource_metadata_url : String
  authorization_servers : Array[String]
  /// Advertised required scopes. The authenticator is responsible for enforcing them.
  required_scopes : String?
  allowed_origins : Array[String]?
}

///|
pub fn AuthConfig::AuthConfig(
  authenticate~ : (String) -> @runtime.Principal?,
  resource_metadata_url~ : String,
  authorization_servers? : Array[String] = [],
  required_scopes? : String = "",
  allowed_origins? : Array[String] = [],
) -> AuthConfig {
  {
    authenticate,
    resource_metadata_url,
    authorization_servers,
    required_scopes: if required_scopes == "" {
      None
    } else {
      Some(required_scopes)
    },
    allowed_origins: if allowed_origins.is_empty() {
      None
    } else {
      Some(allowed_origins)
    },
  }
}

///|
/// Authenticated per-request transport envelope. Identity and cancellation do not enter JSON.
pub(all) struct AuthenticatedRequest {
  message : String
  reply : @async.Queue[String]
  principal : @runtime.Principal?
  cancellation_token : @runtime.CancellationToken
}
