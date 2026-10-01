///|
pub(all) enum ResourceData {
  Text(String)
  Blob(String)
} derive(Eq, Debug)

///|
pub extend ResourceData with Eq::{equal, not_equal}

///|
pub extend ResourceData with Debug::{to_repr}

///|
pub(all) struct ResourceContents {
  uri : String
  mime_type : String?
  data : ResourceData
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Eq, Debug)

///|
pub extend ResourceContents with Eq::{equal, not_equal}

///|
pub extend ResourceContents with Debug::{to_repr}

///|
pub fn ResourceContents::text(
  text : String,
  uri~ : String,
  mime_type? : String,
) -> ResourceContents {
  { uri, mime_type, data: Text(text), meta: None, extensions: {}, }
}

///|
pub fn ResourceContents::blob(
  blob : String,
  uri~ : String,
  mime_type? : String,
) -> ResourceContents {
  { uri, mime_type, data: Blob(blob), meta: None, extensions: {}, }
}

///|
pub fn ResourceContents::from_json(
  value : Json,
) -> ResourceContents raise MCPError {
  let fields = wire_object(value)
  // The wire union permits extra properties, including both text and blob.
  // Prefer text when both are valid; keep the alternate field in extensions.
  let (data, owned) = match fields.get("text") {
    Some(String(text)) => (ResourceData::Text(text), "text")
    _ => (ResourceData::Blob(wire_string(fields, "blob")), "blob")
  }
  {
    uri: wire_string(fields, "uri"),
    mime_type: wire_optional_string(fields, "mimeType"),
    data,
    meta: wire_optional_object(fields, "_meta"),
    extensions: wire_extensions(fields, ["uri", "mimeType", "_meta", owned]),
  }
}

///|
pub impl ToJson for ResourceContents with fn to_json(self) {
  let fields = wire_extensions(self.extensions, ["uri", "mimeType", "_meta"])
  fields.set("uri", Json::string(self.uri))
  wire_put_string(fields, "mimeType", self.mime_type)
  wire_put_meta(fields, self.meta)
  match self.data {
    Text(text) => fields.set("text", Json::string(text))
    Blob(blob) => fields.set("blob", Json::string(blob))
  }
  Json::object(fields)
}

///|
pub extend ResourceContents with ToJson::{to_json}

///|
pub(all) struct ResourceLinkData {
  uri : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  size : Double?
  icons : Array[Icon]?
} derive(Eq, Debug)

///|
pub extend ResourceLinkData with Eq::{equal, not_equal}

///|
pub extend ResourceLinkData with Debug::{to_repr}

///|
fn ResourceLinkData::from_fields(
  fields : Map[String, Json],
) -> ResourceLinkData raise MCPError {
  let size = match fields.get("size") {
    None => None
    Some(Number(n, ..)) if !n.is_inf() && !n.is_nan() && n.trunc() == n =>
      Some(n)
    _ => raise InvalidParams("Resource size must be an integer")
  }
  {
    uri: wire_string(fields, "uri"),
    name: wire_string(fields, "name"),
    title: wire_optional_string(fields, "title"),
    description: wire_optional_string(fields, "description"),
    mime_type: wire_optional_string(fields, "mimeType"),
    size,
    icons: match fields.get("icons") {
      None => None
      Some(Array(icons)) => Some(icons.map(Icon::from_json))
      _ => raise InvalidParams("Invalid resource icons array")
    },
  }
}

///|
fn ResourceLinkData::put_fields(
  self : ResourceLinkData,
  fields : Map[String, Json],
) -> Unit {
  fields.set("uri", Json::string(self.uri))
  fields.set("name", Json::string(self.name))
  wire_put_string(fields, "title", self.title)
  wire_put_string(fields, "description", self.description)
  wire_put_string(fields, "mimeType", self.mime_type)
  match self.size {
    Some(size) => fields.set("size", Json::number(size))
    None => ()
  }
  match self.icons {
    Some(icons) =>
      fields.set("icons", Json::array(icons.map(icon => icon.to_json())))
    None => ()
  }
}
