///|
pub(all) struct ResourceDefinition {
  uri : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  size : Double?
  icons : Array[Icon]?
  metadata : ContentMetadata
} derive(Debug, Eq)

///|
pub fn ResourceDefinition::new(
  uri : String,
  name : String,
  title? : String,
  description? : String,
  mime_type? : String,
  size? : Double,
  icons? : Array[Icon],
  metadata? : ContentMetadata = ContentMetadata::empty(),
) -> ResourceDefinition {
  { uri, name, title, description, mime_type, size, icons, metadata, }
}

///|
pub fn ResourceDefinition::from_json(
  value : Json,
) -> ResourceDefinition raise MCPError {
  let fields = wire_object(value)
  let link = ResourceLinkData::from_fields(fields)
  {
    uri: link.uri,
    name: link.name,
    title: link.title,
    description: link.description,
    mime_type: link.mime_type,
    size: link.size,
    icons: link.icons,
    metadata: ContentMetadata::from_fields(fields, [
      "uri", "name", "title", "description", "mimeType", "size", "icons",
    ]),
  }
}

///|
pub impl ToJson for ResourceDefinition with fn to_json(self) {
  let fields = self.metadata.fields([
    "uri", "name", "title", "description", "mimeType", "size", "icons",
  ])
  let link : ResourceLinkData = {
    uri: self.uri,
    name: self.name,
    title: self.title,
    description: self.description,
    mime_type: self.mime_type,
    size: self.size,
    icons: self.icons,
  }
  link.put_fields(fields)
  Json::object(fields)
}

///|
pub extend ResourceDefinition with Eq::{equal, not_equal}

///|
pub extend ResourceDefinition with Debug::{to_repr}

///|
pub extend ResourceDefinition with ToJson::{to_json}

///|
pub(all) struct ResourceTemplateDefinition {
  uri_template : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  icons : Array[Icon]?
  metadata : ContentMetadata
} derive(Debug, Eq)

///|
pub fn ResourceTemplateDefinition::new(
  uri_template : String,
  name : String,
  title? : String,
  description? : String,
  mime_type? : String,
  icons? : Array[Icon],
  metadata? : ContentMetadata = ContentMetadata::empty(),
) -> ResourceTemplateDefinition {
  { uri_template, name, title, description, mime_type, icons, metadata, }
}

///|
pub fn ResourceTemplateDefinition::from_json(
  value : Json,
) -> ResourceTemplateDefinition raise MCPError {
  let fields = wire_object(value)
  {
    uri_template: wire_string(fields, "uriTemplate"),
    name: wire_string(fields, "name"),
    title: wire_optional_string(fields, "title"),
    description: wire_optional_string(fields, "description"),
    mime_type: wire_optional_string(fields, "mimeType"),
    icons: match fields.get("icons") {
      Some(Array(values)) => Some(values.map(Icon::from_json))
      None => None
      _ => raise InvalidParams("Invalid resource template icons")
    },
    metadata: ContentMetadata::from_fields(fields, [
      "uriTemplate", "name", "title", "description", "mimeType", "icons",
    ]),
  }
}

///|
pub impl ToJson for ResourceTemplateDefinition with fn to_json(self) {
  let fields = self.metadata.fields([
    "uriTemplate", "name", "title", "description", "mimeType", "icons",
  ])
  fields.set("uriTemplate", Json::string(self.uri_template))
  fields.set("name", Json::string(self.name))
  wire_put_string(fields, "title", self.title)
  wire_put_string(fields, "description", self.description)
  wire_put_string(fields, "mimeType", self.mime_type)
  match self.icons {
    Some(values) => fields.set("icons", Json::array(values.map(Icon::to_json)))
    None => ()
  }
  Json::object(fields)
}

///|
pub extend ResourceTemplateDefinition with Eq::{equal, not_equal}

///|
pub extend ResourceTemplateDefinition with Debug::{to_repr}

///|
pub extend ResourceTemplateDefinition with ToJson::{to_json}
