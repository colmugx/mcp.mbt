///|
pub(all) enum CacheScope {
  Public
  Private
} derive(Debug, Eq)

///|
/// Shared result fields retain wire presence; extensions are top-level fields.
pub(all) struct ResultMetadata {
  result_type : String?
  ttl_ms : Double?
  cache_scope : CacheScope?
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn ResultMetadata::empty() -> ResultMetadata {
  {
    result_type: None,
    ttl_ms: None,
    cache_scope: None,
    meta: None,
    extensions: Map([]),
  }
}

///|
/// Decode metadata without retaining the caller's owned result-body fields.
pub fn ResultMetadata::from_json(
  value : Json,
  body_fields~ : Array[String],
) -> ResultMetadata raise MCPError {
  let fields = wire_object(value)
  let ttl_ms = match fields.get("ttlMs") {
    None => None
    Some(Number(n, ..)) => {
      guard !n.is_nan() && !n.is_inf() && n >= 0 && n.trunc() == n else {
        raise InvalidParams(
          "Invalid ttlMs: expected a nonnegative finite integer",
        )
      }
      Some(n)
    }
    _ => raise InvalidParams("Invalid ttlMs number")
  }
  let cache_scope = match fields.get("cacheScope") {
    None => None
    Some(String("public")) => Some(Public)
    Some(String("private")) => Some(Private)
    _ => raise InvalidParams("Invalid cacheScope")
  }
  {
    result_type: wire_optional_string(fields, "resultType"),
    ttl_ms,
    cache_scope,
    meta: wire_optional_object(fields, "_meta"),
    extensions: wire_extensions(
      fields,
      body_fields + ["resultType", "ttlMs", "cacheScope", "_meta"],
    ),
  }
}

///|
pub fn ResultMetadata::server_info(self : ResultMetadata) -> Json? {
  match self.meta {
    Some(meta) => meta.get("io.modelcontextprotocol/serverInfo")
    None => None
  }
}

///|
fn ResultMetadata::to_fields(self : ResultMetadata) -> Map[String, Json] {
  let fields = wire_extensions(self.extensions, [
    "resultType", "ttlMs", "cacheScope", "_meta",
  ])
  wire_put_string(fields, "resultType", self.result_type)
  match self.ttl_ms {
    Some(n) => fields.set("ttlMs", Json::number(n))
    None => ()
  }
  match self.cache_scope {
    Some(Public) => fields.set("cacheScope", Json::string("public"))
    Some(Private) => fields.set("cacheScope", Json::string("private"))
    None => ()
  }
  wire_put_meta(fields, self.meta)
  fields
}

///|
pub impl ToJson for ResultMetadata with fn to_json(self) {
  Json::object(self.to_fields())
}

///|
pub extend CacheScope with Eq::{equal, not_equal}

///|
pub extend CacheScope with Debug::{to_repr}

///|
pub extend ResultMetadata with Eq::{equal, not_equal}

///|
pub extend ResultMetadata with Debug::{to_repr}

///|
pub extend ResultMetadata with ToJson::{to_json}
