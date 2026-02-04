///|
/// SchemaType represents the type of a field in the schema
pub enum SchemaType {
  Str
  Int
  Num
  Bool
  Arr(SchemaType)
  Obj
}

///|
/// FieldDef represents a single field definition
struct FieldDef {
  name : String
  field_type : SchemaType
  description : String
  required : Bool
}

///|
/// SchemaBuilder provides a fluent API for building JSON schemas
pub struct SchemaBuilder {
  fields : Array[FieldDef]
}

///|
/// Create a new schema builder
pub fn schema_builder() -> SchemaBuilder {
  { fields: [] }
}

///|
/// Add a field to the schema
pub fn SchemaBuilder::field(
  self : SchemaBuilder,
  name : String,
  field_type : SchemaType,
  required? : Bool = false,
  desc? : String = "",
) -> SchemaBuilder {
  let field_def : FieldDef = { name, field_type, description: desc, required }
  { fields: self.fields + [field_def] }
}

///|
/// Build the final JsonSchema
pub fn SchemaBuilder::build(
  self : SchemaBuilder,
  desc? : String = "",
) -> JsonSchema {
  let properties_map : Map[String, JsonSchema] = Map::default()
  let required_fields : Array[String] = []
  for field_def in self.fields {
    let field_schema = type_to_schema(
      field_def.field_type,
      field_def.description,
    )
    properties_map.set(field_def.name, field_schema)
    if field_def.required {
      required_fields.push(field_def.name)
    }
  }
  obj_schema(properties_map, required_fields, desc~)
}

///|
/// Convert SchemaType to JsonSchema
fn type_to_schema(schema_type : SchemaType, desc : String) -> JsonSchema {
  match schema_type {
    Str => str_schema(desc~)
    Int => int_schema(desc~)
    Num => num_schema(desc~)
    Bool => bool_schema(desc~)
    Arr(item_type) => {
      let item_schema = type_to_schema(item_type, "")
      arr_schema(item_schema, desc~)
    }
    Obj =>
      {
        type_name: "object",
        description: desc,
        properties: None,
        required: None,
        items: None,
        default: None,
      }
  }
}

///|
/// Type constructor: String type
pub fn str_type() -> SchemaType {
  Str
}

///|
/// Type constructor: Integer type
pub fn int_type() -> SchemaType {
  Int
}

///|
/// Type constructor: Number type
pub fn num_type() -> SchemaType {
  Num
}

///|
/// Type constructor: Boolean type
pub fn bool_type() -> SchemaType {
  Bool
}

///|
/// Type constructor: Array type
pub fn arr_type(item_type : SchemaType) -> SchemaType {
  Arr(item_type)
}

///|
/// Type constructor: Object type
pub fn obj_type() -> SchemaType {
  Obj
}
