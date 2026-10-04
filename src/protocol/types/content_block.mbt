///|
pub(all) enum ContentBlock {
  Text(String, metadata~ : ContentMetadata)
  Image(String, mime_type~ : String, metadata~ : ContentMetadata)
  Audio(String, mime_type~ : String, metadata~ : ContentMetadata)
  ResourceLink(ResourceLinkData, metadata~ : ContentMetadata)
  EmbeddedResource(ResourceContents, metadata~ : ContentMetadata)
  /// A future content type, retained without interpreting its fields.
  Unknown(Json)
} derive(Eq, Debug)

///|
pub extend ContentBlock with Eq::{equal, not_equal}

///|
pub extend ContentBlock with Debug::{to_repr}

///|
pub fn ContentBlock::text(
  text : String,
  metadata? : ContentMetadata = ContentMetadata::empty(),
) -> ContentBlock {
  Text(text, metadata~)
}

///|
pub fn ContentBlock::image(
  data : String,
  mime_type~ : String,
  metadata? : ContentMetadata = ContentMetadata::empty(),
) -> ContentBlock {
  Image(data, mime_type~, metadata~)
}

///|
pub fn ContentBlock::audio(
  data : String,
  mime_type~ : String,
  metadata? : ContentMetadata = ContentMetadata::empty(),
) -> ContentBlock {
  Audio(data, mime_type~, metadata~)
}

///|
pub fn ContentBlock::resource_link(
  uri : String,
  name~ : String,
  title? : String,
  description? : String,
  mime_type? : String,
  size? : Double,
  icons? : Array[Icon],
  metadata? : ContentMetadata = ContentMetadata::empty(),
) -> ContentBlock {
  ResourceLink(
    { uri, name, title, description, mime_type, size, icons, },
    metadata~,
  )
}

///|
pub fn ContentBlock::resource(
  resource : ResourceContents,
  metadata? : ContentMetadata = ContentMetadata::empty(),
) -> ContentBlock {
  EmbeddedResource(resource, metadata~)
}

///|
let resource_link_fields : Array[String] = [
  "type", "uri", "name", "title", "description", "mimeType", "size", "icons",
]

///|
pub fn ContentBlock::from_json(value : Json) -> ContentBlock raise MCPError {
  let fields = wire_object(value)
  match wire_string(fields, "type") {
    "text" =>
      Text(
        wire_string(fields, "text"),
        metadata=ContentMetadata::from_fields(fields, ["type", "text"]),
      )
    "image" =>
      Image(
        wire_string(fields, "data"),
        mime_type=wire_string(fields, "mimeType"),
        metadata=ContentMetadata::from_fields(fields, [
          "type", "data", "mimeType",
        ]),
      )
    "audio" =>
      Audio(
        wire_string(fields, "data"),
        mime_type=wire_string(fields, "mimeType"),
        metadata=ContentMetadata::from_fields(fields, [
          "type", "data", "mimeType",
        ]),
      )
    "resource_link" =>
      ResourceLink(
        ResourceLinkData::from_fields(fields),
        metadata=ContentMetadata::from_fields(fields, resource_link_fields),
      )
    "resource" => {
      let resource = match fields.get("resource") {
        Some(resource) => ResourceContents::from_json(resource)
        None => raise InvalidParams("Missing embedded resource")
      }
      EmbeddedResource(
        resource,
        metadata=ContentMetadata::from_fields(fields, ["type", "resource"]),
      )
    }
    _ => Unknown(Json::object(fields.copy()))
  }
}

///|
pub impl ToJson for ContentBlock with fn to_json(self) {
  match self {
    Text(text, metadata~) => {
      let fields = metadata.fields(["type", "text"])
      fields.set("type", Json::string("text"))
      fields.set("text", Json::string(text))
      Json::object(fields)
    }
    Image(data, mime_type~, metadata~) => {
      let fields = metadata.fields(["type", "data", "mimeType"])
      fields.set("type", Json::string("image"))
      fields.set("data", Json::string(data))
      fields.set("mimeType", Json::string(mime_type))
      Json::object(fields)
    }
    Audio(data, mime_type~, metadata~) => {
      let fields = metadata.fields(["type", "data", "mimeType"])
      fields.set("type", Json::string("audio"))
      fields.set("data", Json::string(data))
      fields.set("mimeType", Json::string(mime_type))
      Json::object(fields)
    }
    ResourceLink(link, metadata~) => {
      let fields = metadata.fields(resource_link_fields)
      fields.set("type", Json::string("resource_link"))
      link.put_fields(fields)
      Json::object(fields)
    }
    EmbeddedResource(resource, metadata~) => {
      let fields = metadata.fields(["type", "resource"])
      fields.set("type", Json::string("resource"))
      fields.set("resource", resource.to_json())
      Json::object(fields)
    }
    Unknown(Object(fields)) => Json::object(fields.copy())
    Unknown(value) => value
  }
}

///|
pub extend ContentBlock with ToJson::{to_json}
