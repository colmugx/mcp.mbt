///|
pub(all) struct ResourceReadResult {
  contents : Array[ResourceContents]
  metadata : ResultMetadata
} derive(Debug, Eq)

///|
pub fn ResourceReadResult::new(
  contents : Array[ResourceContents],
  metadata? : ResultMetadata = ResultMetadata::empty(),
) -> ResourceReadResult {
  { contents, metadata, }
}

///|
pub fn ResourceReadResult::text(
  text : String,
  uri~ : String,
  mime_type? : String,
) -> ResourceReadResult {
  ResourceReadResult::new([ResourceContents::text(text, uri~, mime_type?)])
}

///|
pub fn ResourceReadResult::blob(
  blob : String,
  uri~ : String,
  mime_type? : String,
) -> ResourceReadResult {
  ResourceReadResult::new([ResourceContents::blob(blob, uri~, mime_type?)])
}

///|
pub fn ResourceReadResult::from_json(
  value : Json,
) -> ResourceReadResult raise MCPError {
  let fields = wire_object(value)
  let contents = match fields.get("contents") {
    Some(Array(values)) => values.map(ResourceContents::from_json)
    _ => raise InvalidParams("Missing or invalid resource contents array")
  }
  {
    contents,
    metadata: ResultMetadata::from_json(value, body_fields=["contents"]),
  }
}

///|
pub impl ToJson for ResourceReadResult with fn to_json(self) {
  let fields = wire_extensions(self.metadata.to_fields(), ["contents"])
  fields.set(
    "contents",
    Json::array(self.contents.map(ResourceContents::to_json)),
  )
  Json::object(fields)
}

///|
pub extend ResourceReadResult with Eq::{equal, not_equal}

///|
pub extend ResourceReadResult with Debug::{to_repr}

///|
pub extend ResourceReadResult with ToJson::{to_json}
