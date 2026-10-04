///|
/// Advisory hints, not an authorization or safety policy.
pub(all) struct ToolAnnotations {
  title : String?
  read_only_hint : Bool?
  destructive_hint : Bool?
  idempotent_hint : Bool?
  open_world_hint : Bool?
  extensions : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn ToolAnnotations::new(
  title? : String,
  read_only_hint? : Bool,
  destructive_hint? : Bool,
  idempotent_hint? : Bool,
  open_world_hint? : Bool,
) -> ToolAnnotations {
  {
    title,
    read_only_hint,
    destructive_hint,
    idempotent_hint,
    open_world_hint,
    extensions: Map([]),
  }
}

///|
pub fn ToolAnnotations::from_json(
  value : Json,
) -> ToolAnnotations raise MCPError {
  let fields = wire_object(value)
  {
    title: wire_optional_string(fields, "title"),
    read_only_hint: wire_optional_bool(fields, "readOnlyHint"),
    destructive_hint: wire_optional_bool(fields, "destructiveHint"),
    idempotent_hint: wire_optional_bool(fields, "idempotentHint"),
    open_world_hint: wire_optional_bool(fields, "openWorldHint"),
    extensions: wire_extensions(fields, [
      "title", "readOnlyHint", "destructiveHint", "idempotentHint", "openWorldHint",
    ]),
  }
}

///|
pub impl ToJson for ToolAnnotations with fn to_json(self) {
  let fields = wire_extensions(self.extensions, [
    "title", "readOnlyHint", "destructiveHint", "idempotentHint", "openWorldHint",
  ])
  wire_put_string(fields, "title", self.title)
  wire_put_bool(fields, "readOnlyHint", self.read_only_hint)
  wire_put_bool(fields, "destructiveHint", self.destructive_hint)
  wire_put_bool(fields, "idempotentHint", self.idempotent_hint)
  wire_put_bool(fields, "openWorldHint", self.open_world_hint)
  Json::object(fields)
}

///|
pub(all) struct ToolDefinition {
  name : String
  title : String?
  description : String?
  input_schema : Json
  output_schema : Json?
  annotations : ToolAnnotations?
  icons : Array[Icon]?
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn ToolDefinition::new(
  name : String,
  input_schema : Json,
  title? : String,
  description? : String,
  output_schema? : Json,
  annotations? : ToolAnnotations,
  icons? : Array[Icon],
  meta? : Map[String, Json],
) -> ToolDefinition {
  {
    name,
    title,
    description,
    input_schema,
    output_schema,
    annotations,
    icons,
    meta,
    extensions: Map([]),
  }
}

///|
pub fn ToolDefinition::from_json(value : Json) -> ToolDefinition raise MCPError {
  let fields = wire_object(value)
  let input_schema = match fields.get("inputSchema") {
    Some(Object(schema)) => {
      guard schema.get("type") is Some(String("object")) else {
        raise InvalidParams("Tool inputSchema must have type 'object'")
      }
      ignore(wire_optional_string(schema, "$schema"))
      Json::object(schema.copy())
    }
    _ => raise InvalidParams("Missing or invalid tool inputSchema object")
  }
  let output_schema = match wire_optional_object(fields, "outputSchema") {
    Some(schema) => {
      ignore(wire_optional_string(schema, "$schema"))
      Some(Json::object(schema))
    }
    None => None
  }
  {
    name: wire_string(fields, "name"),
    title: wire_optional_string(fields, "title"),
    description: wire_optional_string(fields, "description"),
    input_schema,
    output_schema,
    annotations: match fields.get("annotations") {
      Some(value) => Some(ToolAnnotations::from_json(value))
      None => None
    },
    icons: match fields.get("icons") {
      Some(Array(values)) => Some(values.map(Icon::from_json))
      None => None
      _ => raise InvalidParams("Invalid tool icons array")
    },
    meta: wire_optional_object(fields, "_meta"),
    extensions: wire_extensions(fields, [
      "name", "title", "description", "inputSchema", "outputSchema", "annotations",
      "icons", "_meta",
    ]),
  }
}

///|
pub impl ToJson for ToolDefinition with fn to_json(self) {
  let fields = wire_extensions(self.extensions, [
    "name", "title", "description", "inputSchema", "outputSchema", "annotations",
    "icons", "_meta",
  ])
  fields.set("name", self.name.to_json())
  fields.set("inputSchema", self.input_schema)
  wire_put_string(fields, "title", self.title)
  wire_put_string(fields, "description", self.description)
  match self.output_schema {
    Some(schema) => fields.set("outputSchema", schema)
    None => ()
  }
  match self.annotations {
    Some(value) => fields.set("annotations", value.to_json())
    None => ()
  }
  match self.icons {
    Some(values) => fields.set("icons", Json::array(values.map(Icon::to_json)))
    None => ()
  }
  wire_put_meta(fields, self.meta)
  Json::object(fields)
}

///|
pub extend ToolAnnotations with Eq::{equal, not_equal}

///|
pub extend ToolAnnotations with Debug::{to_repr}

///|
pub extend ToolAnnotations with ToJson::{to_json}

///|
pub extend ToolDefinition with ToJson::{to_json}
