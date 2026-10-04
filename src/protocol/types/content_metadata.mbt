///|
pub(all) enum Role {
  User
  Assistant
} derive(Eq, Debug)

///|
pub extend Role with Eq::{equal, not_equal}

///|
pub extend Role with Debug::{to_repr}

///|
pub extend Role with ToJson::{to_json}

///|
pub impl ToJson for Role with fn to_json(self) {
  match self {
    User => Json::string("user")
    Assistant => Json::string("assistant")
  }
}

///|
fn Role::from_json(value : Json) -> Role raise MCPError {
  match value {
    String("user") => User
    String("assistant") => Assistant
    _ => raise InvalidParams("Invalid annotation audience role")
  }
}

///|
pub(all) struct Annotations {
  audience : Array[Role]?
  priority : Double?
  last_modified : String?
  extensions : Map[String, Json]
} derive(Eq, Debug)

///|
pub extend Annotations with Eq::{equal, not_equal}

///|
pub extend Annotations with Debug::{to_repr}

///|
pub fn Annotations::from_json(value : Json) -> Annotations raise MCPError {
  let fields = wire_object(value)
  let audience = match fields.get("audience") {
    None => None
    Some(Array(roles)) => Some(roles.map(Role::from_json))
    _ => raise InvalidParams("Invalid annotation audience array")
  }
  let priority = match fields.get("priority") {
    None => None
    Some(Number(n, ..)) if n >= 0.0 && n <= 1.0 => Some(n)
    _ => raise InvalidParams("Annotation priority must be between 0 and 1")
  }
  {
    audience,
    priority,
    last_modified: wire_optional_string(fields, "lastModified"),
    extensions: wire_extensions(fields, ["audience", "priority", "lastModified"]),
  }
}

///|
pub impl ToJson for Annotations with fn to_json(self) {
  let fields = wire_extensions(self.extensions, [
    "audience", "priority", "lastModified",
  ])
  match self.audience {
    Some(roles) =>
      fields.set("audience", Json::array(roles.map(role => role.to_json())))
    None => ()
  }
  match self.priority {
    Some(n) => fields.set("priority", Json::number(n))
    None => ()
  }
  wire_put_string(fields, "lastModified", self.last_modified)
  Json::object(fields)
}

///|
pub extend Annotations with ToJson::{to_json}

///|
pub(all) enum IconTheme {
  Light
  Dark
} derive(Eq, Debug)

///|
pub extend IconTheme with Eq::{equal, not_equal}

///|
pub extend IconTheme with Debug::{to_repr}

///|
pub(all) struct Icon {
  src : String
  mime_type : String?
  sizes : Array[String]?
  theme : IconTheme?
  extensions : Map[String, Json]
} derive(Eq, Debug)

///|
pub extend Icon with Eq::{equal, not_equal}

///|
pub extend Icon with Debug::{to_repr}

///|
pub fn Icon::from_json(value : Json) -> Icon raise MCPError {
  let fields = wire_object(value)
  let theme = match fields.get("theme") {
    None => None
    Some(String("light")) => Some(Light)
    Some(String("dark")) => Some(Dark)
    _ => raise InvalidParams("Invalid icon theme")
  }
  {
    src: wire_string(fields, "src"),
    mime_type: wire_optional_string(fields, "mimeType"),
    sizes: wire_optional_strings(fields, "sizes"),
    theme,
    extensions: wire_extensions(fields, ["src", "mimeType", "sizes", "theme"]),
  }
}

///|
pub impl ToJson for Icon with fn to_json(self) {
  let fields = wire_extensions(self.extensions, [
    "src", "mimeType", "sizes", "theme",
  ])
  fields.set("src", Json::string(self.src))
  wire_put_string(fields, "mimeType", self.mime_type)
  match self.sizes {
    Some(sizes) => fields.set("sizes", Json::array(sizes.map(Json::string)))
    None => ()
  }
  match self.theme {
    Some(Light) => fields.set("theme", Json::string("light"))
    Some(Dark) => fields.set("theme", Json::string("dark"))
    None => ()
  }
  Json::object(fields)
}

///|
pub extend Icon with ToJson::{to_json}

///|
pub(all) struct ContentMetadata {
  annotations : Annotations?
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Eq, Debug)

///|
pub extend ContentMetadata with Eq::{equal, not_equal}

///|
pub extend ContentMetadata with Debug::{to_repr}

///|
pub fn ContentMetadata::empty() -> ContentMetadata {
  { annotations: None, meta: None, extensions: {}, }
}

///|
fn ContentMetadata::from_fields(
  fields : Map[String, Json],
  owned : Array[String],
) -> ContentMetadata raise MCPError {
  {
    annotations: match fields.get("annotations") {
      Some(value) => Some(Annotations::from_json(value))
      None => None
    },
    meta: wire_optional_object(fields, "_meta"),
    extensions: wire_extensions(fields, owned + ["annotations", "_meta"]),
  }
}

///|
fn ContentMetadata::fields(
  self : ContentMetadata,
  owned : Array[String],
) -> Map[String, Json] {
  let fields = wire_extensions(
    self.extensions,
    owned + ["annotations", "_meta"],
  )
  match self.annotations {
    Some(annotations) => fields.set("annotations", annotations.to_json())
    None => ()
  }
  wire_put_meta(fields, self.meta)
  fields
}
