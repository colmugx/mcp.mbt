///|
pub(open) trait Params {
  schema() -> JsonSchema
  from_json(Json) -> Self raise ToolError
  to_json(Self) -> Json
}

///|
pub struct JsonSchema {
  type_name : String
  description : String
  properties : Map[String, JsonSchema]?
  required : Array[String]?
  items : JsonSchema?
  default : Json?
} derive(Show)

///|
pub suberror ToolError {
  ToolError(String)
}

///|
pub fn tool_error(msg : String) -> ToolError {
  ToolError(msg)
}

///|
pub(all) enum ParamKind {
  String
  Integer
  Number
  Boolean
  Array(ParamKind)
  Object(Map[String, ParamKind])
}

///|
pub fn str_schema(desc? : String = "") -> JsonSchema {
  {
    type_name: "string",
    description: desc,
    properties: None,
    required: None,
    items: None,
    default: None,
  }
}

///|
pub fn int_schema(desc? : String = "") -> JsonSchema {
  {
    type_name: "integer",
    description: desc,
    properties: None,
    required: None,
    items: None,
    default: None,
  }
}

///|
pub fn num_schema(desc? : String = "") -> JsonSchema {
  {
    type_name: "number",
    description: desc,
    properties: None,
    required: None,
    items: None,
    default: None,
  }
}

///|
pub fn bool_schema(desc? : String = "") -> JsonSchema {
  {
    type_name: "boolean",
    description: desc,
    properties: None,
    required: None,
    items: None,
    default: None,
  }
}

///|
pub fn arr_schema(item : JsonSchema, desc? : String = "") -> JsonSchema {
  {
    type_name: "array",
    description: desc,
    properties: None,
    required: None,
    items: Some(item),
    default: None,
  }
}

///|
pub fn obj_schema(
  props : Map[String, JsonSchema],
  required : Array[String],
  desc? : String = "",
) -> JsonSchema {
  {
    type_name: "object",
    description: desc,
    properties: Some(props),
    required: Some(required),
    items: None,
    default: None,
  }
}

///|
pub fn JsonSchema::to_json(self : JsonSchema) -> Json {
  let obj = {}
  obj["type"] = Json::string(self.type_name)
  if self.description != "" {
    obj["description"] = Json::string(self.description)
  }
  match self.properties {
    Some(props) => {
      let props_obj = {}
      for name, schema in props {
        props_obj[name] = schema.to_json()
      }
      obj["properties"] = Json::object(props_obj)
    }
    None => ()
  }
  match self.required {
    Some(req) =>
      obj["required"] = Json::array(req.map(fn(s) { Json::string(s) }))
    None => ()
  }
  match self.items {
    Some(item) => obj["items"] = item.to_json()
    None => ()
  }
  match self.default {
    Some(d) => obj["default"] = d
    None => ()
  }
  Json::object(obj)
}

///|
pub impl Params for String with schema() -> JsonSchema {
  str_schema(desc="String value")
}

///|
pub impl Params for String with from_json(j : Json) -> String raise ToolError {
  match j {
    String(s) => s
    _ => raise ToolError("Expected string")
  }
}

///|
pub impl Params for String with to_json(self : String) -> Json {
  Json::string(self)
}

///|
pub impl Params for Int with schema() -> JsonSchema {
  int_schema(desc="Integer value")
}

///|
pub impl Params for Int with from_json(j : Json) -> Int raise ToolError {
  match j {
    Number(n, ..) => n.to_int()
    _ => raise ToolError("Expected integer")
  }
}

///|
pub impl Params for Int with to_json(self : Int) -> Json {
  Json::number(self.to_double())
}

///|
pub impl Params for Double with schema() -> JsonSchema {
  num_schema(desc="Number value")
}

///|
pub impl Params for Double with from_json(j : Json) -> Double raise ToolError {
  match j {
    Number(n, ..) => n
    _ => raise ToolError("Expected number")
  }
}

///|
pub impl Params for Double with to_json(self : Double) -> Json {
  Json::number(self)
}

///|
pub impl Params for Bool with schema() -> JsonSchema {
  bool_schema(desc="Boolean value")
}

///|
pub impl Params for Bool with from_json(j : Json) -> Bool raise ToolError {
  match j {
    True => true
    False => false
    _ => raise ToolError("Expected boolean")
  }
}

///|
pub impl Params for Bool with to_json(self : Bool) -> Json {
  Json::boolean(self)
}

///|
pub impl[T : Params] Params for Array[T] with schema() -> JsonSchema {
  arr_schema(T::schema(), desc="Array of items")
}

///|
pub impl[T : Params] Params for Array[T] with from_json(j : Json) -> Array[T] raise ToolError {
  match j {
    Array(arr) => arr.map(fn(item) { T::from_json(item) })
    _ => raise ToolError("Expected array")
  }
}

///|
pub impl[T : Params] Params for Array[T] with to_json(self : Array[T]) -> Json {
  Json::array(self.map(fn(item) { item.to_json() }))
}

///|
pub impl[T : Params] Params for T? with schema() -> JsonSchema {
  T::schema()
}

///|
pub impl[T : Params] Params for T? with from_json(j : Json) -> T? raise ToolError {
  match j {
    Null => None
    _ => Some(T::from_json(j))
  }
}

///|
pub impl[T : Params] Params for T? with to_json(self : T?) -> Json {
  match self {
    Some(v) => v.to_json()
    None => Json::null()
  }
}
