///|
fn expand_params_to_json(params : Array[@tool.ParamDef]) -> Json {
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

///|
pub fn[T : @tool.Tool] ToolRegistry::register_trait_tool(
  self : ToolRegistry,
  tool : T,
) -> Unit {
  let name = tool.name()
  let description = tool.description()
  let params = tool.params()
  let input_schema = expand_params_to_json(params)
  let handler = async fn(
    args : Json,
  ) -> Result[@tool.ToolResult, @types.MCPError] {
    Ok(tool.execute(args))
  }
  self.register(name, description, input_schema, handler)
}
