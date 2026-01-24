///|
/// Create a string parameter definition
pub fn string_param(name : String, description : String) -> @tool.ParamDef {
  { name, description, type_: "string", required: true }
}

///|
/// Create an optional string parameter definition
pub fn optional_string_param(name : String, description : String) -> @tool.ParamDef {
  { name, description, type_: "string", required: false }
}

///|
/// Create a number parameter definition
pub fn number_param(name : String, description : String) -> @tool.ParamDef {
  { name, description, type_: "number", required: true }
}

///|
/// Create an optional number parameter definition
pub fn optional_number_param(name : String, description : String) -> @tool.ParamDef {
  { name, description, type_: "number", required: false }
}

///|
/// Create a boolean parameter definition
pub fn boolean_param(name : String, description : String) -> @tool.ParamDef {
  { name, description, type_: "boolean", required: true }
}

///|
/// Create an optional boolean parameter definition
pub fn optional_boolean_param(name : String, description : String) -> @tool.ParamDef {
  { name, description, type_: "boolean", required: false }
}

///|
/// Expand array of parameter definitions to JSON schema
pub fn expand_params_to_json(params : Array[@tool.ParamDef]) -> Json {
  let properties_map : Map[String, Json] = Map::default()
  for param in params {
    let prop_map : Map[String, Json] = Map::default()
    prop_map.set("type", Json::string(param.type_))
    if not(param.description.is_empty()) {
      prop_map.set("description", Json::string(param.description))
    }
    properties_map.set(param.name, Json::object(prop_map))
  }

  let required_list : Array[Json] = []
  for param in params {
    if param.required {
      required_list.push(Json::string(param.name))
    }
  }

  let schema_map : Map[String, Json] = Map::default()
  schema_map.set("type", Json::string("object"))
  schema_map.set("properties", Json::object(properties_map))
  schema_map.set("required", Json::array(required_list))
  Json::object(schema_map)
}
