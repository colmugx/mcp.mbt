///|
pub trait ToToolResult {
  to_tool_result(Self) -> @tool.ToolResult
}

///|
pub impl ToToolResult for String with to_tool_result(self : String) -> @tool.ToolResult {
  @tool.ToolResult::text(self)
}

///|
pub impl ToToolResult for Int with to_tool_result(self : Int) -> @tool.ToolResult {
  @tool.ToolResult::text(self.to_string())
}

///|
pub impl ToToolResult for Bool with to_tool_result(self : Bool) -> @tool.ToolResult {
  @tool.ToolResult::text(self.to_string())
}

///|
pub impl ToToolResult for Double with to_tool_result(self : Double) -> @tool.ToolResult {
  @tool.ToolResult::text(self.to_string())
}

///|
pub impl ToToolResult for @tool.ToolResult with to_tool_result(
  self : @tool.ToolResult,
) -> @tool.ToolResult {
  self
}

///|
pub impl ToToolResult for Unit with to_tool_result(_self : Unit) -> @tool.ToolResult {
  @tool.ToolResult::text("ok")
}

///|
pub(all) struct ToolWrapper {
  name_impl : () -> String
  description_impl : () -> String
  params_impl : () -> Array[@tool.ParamDef]
  execute_impl : (Json) -> @tool.ToolResult
}

///|
pub impl @tool.Tool for ToolWrapper with name(self) -> String {
  (self.name_impl)()
}

///|
pub impl @tool.Tool for ToolWrapper with description(self) -> String {
  (self.description_impl)()
}

///|
pub impl @tool.Tool for ToolWrapper with params(self) -> Array[@tool.ParamDef] {
  (self.params_impl)()
}

///|
pub impl @tool.Tool for ToolWrapper with execute(self, json) -> @tool.ToolResult {
  (self.execute_impl)(json)
}

///|
pub fn[Args : Params, Ret : ToToolResult] tool_fn(
  handler : (Args) -> Ret,
  name~ : String,
  description~ : String,
) -> ToolWrapper {
  let arg_schema = Args::schema()
  {
    name_impl: fn() -> String { name },
    description_impl: fn() -> String { description },
    params_impl: fn() -> Array[@tool.ParamDef] {
      let mut params : Array[@tool.ParamDef] = []
      match arg_schema.properties {
        Some(props) => {
          let required = match arg_schema.required {
            Some(r) => r
            None => []
          }
          for name, prop_schema in props {
            let type_str = prop_schema.type_name
            let is_required = required.contains(name)
            params = params +
              [
                {
                  name,
                  description: prop_schema.description,
                  type_: type_str,
                  required: is_required,
                },
              ]
          }
        }
        None => ()
      }
      params
    },
    execute_impl: fn(json) -> @tool.ToolResult {
      try {
        let args = Args::from_json(json)
        let result = handler(args)
        result.to_tool_result()
      } catch {
        ToolError(msg) => @tool.ToolResult::error("Parameter error: " + msg)
      }
    },
  }
}

///|
pub fn simple_tool(
  name : String,
  description : String,
  handler : (Json) -> @tool.ToolResult,
) -> ToolWrapper {
  {
    name_impl: fn() -> String { name },
    description_impl: fn() -> String { description },
    params_impl: fn() -> Array[@tool.ParamDef] { [] },
    execute_impl: handler,
  }
}
