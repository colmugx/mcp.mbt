///|
priv enum ValueType {
  NullType
  BooleanType
  NumberType
  IntegerType
  StringType
  ArrayType
  ObjectType
}

///|
priv enum Plan {
  Accept
  Reject(String)
  Rules(Array[Rule])
}

///|
priv enum Rule {
  Types(Array[ValueType], String)
  Constant(Json, String)
  Enumeration(Array[Json], String)
  Lower(ExactNumber, Bool, String)
  Upper(ExactNumber, Bool, String)
  Multiple(ExactNumber, String)
  StringLength(Int?, Int?, String)
  Pattern(PatternSupport, String)
  Objects(ObjectPlan)
  Arrays(ArrayPlan)
  All(Array[Plan], String)
  Any(Array[Plan], String)
  One(Array[Plan], String)
  Negate(Plan, String)
  Conditional(Plan, Plan?, Plan?)
}

///|
priv struct ObjectPlan {
  path : String
  properties : Map[String, Plan]
  patterns : Array[(PatternSupport, Plan)]
  additional : Plan?
  required : Array[String]
  names : Plan?
  minimum : Int?
  maximum : Int?
  dependent_required : Array[(String, Array[String])]
  dependent_schemas : Array[(String, Plan)]
}

///|
priv struct ArrayPlan {
  path : String
  prefix : Array[Plan]
  items : Plan?
  contains : Plan?
  min_contains : Int
  max_contains : Int?
  minimum : Int?
  maximum : Int?
  unique : Bool
}

///|
/// An owned, precompiled 2020-12 validation plan. Compilation does not mutate
/// the source document; constants and enumerations are copied into the plan.
pub struct Schema {
  priv plan : Plan
}

///|
fn pointer_step(path : String, key : String) -> String {
  path + "/" + key.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
fn owned_json(value : Json) -> Json {
  match value {
    Object(members) => {
      let copy : Map[String, Json] = Map([])
      for key, child in members {
        copy.set(key, owned_json(child))
      }
      Json::object(copy)
    }
    Array(values) => Json::array(values.map(owned_json))
    _ => value
  }
}
