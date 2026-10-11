///| Tool Trait Unit Tests

///| Comprehensive tests for Tool trait and ToolResult

///|
test "ToolResult and ContentBlock constructors smoke" {
  let text = @server.ToolResult::text("Success")
  @debug.assert_eq(text.is_error, Some(false))
  match text.content[0] {
    Text(msg, ..) => @debug.assert_eq(msg, "Success")
    _ => panic()
  }
  let error = @server.ToolResult::error("Failed")
  @debug.assert_eq(error.is_error, Some(true))
  let items = [
    @server.ContentBlock::text("Line 1"),
    @server.ContentBlock::image("base64data", mime_type="image/png"),
    @server.ContentBlock::resource_link(
      "file:///path/to/resource.txt",
      name="resource.txt",
    ),
  ]
  let multi = @server.ToolResult::success(items)
  @debug.assert_eq(multi.is_error, Some(false))
  @debug.assert_eq(multi.content.length(), 3)
  match multi.content[1] {
    Image(_, mime_type~, ..) => @debug.assert_eq(mime_type, "image/png")
    _ => panic()
  }
  match multi.content[2] {
    ResourceLink(link, ..) =>
      @debug.assert_eq(link.uri, "file:///path/to/resource.txt")
    _ => panic()
  }
  @debug.assert_eq(@server.ToolResult::success([]).content.length(), 0)
}

///|
/// Helper Function Tests
test "get_string extracts, rejects missing/wrong-type/non-object" {
  match @server.get_string(Json::object({ "name": "MoonBit" }), "name") {
    Ok(name) => @debug.assert_eq(name, "MoonBit")
    Err(_) => panic()
  }
  match @server.get_string(Json::object({ "other": "value" }), "name") {
    Err(result) => @debug.assert_eq(result.is_error, Some(true))
    Ok(_) => panic()
  }
  match @server.get_string(Json::object({ "name": 42.0 }), "name") {
    Err(result) => {
      @debug.assert_eq(result.is_error, Some(true))
      match result.content[0] {
        Text(msg, ..) => assert_true(msg.contains("not a string"))
        _ => panic()
      }
    }
    Ok(_) => panic()
  }
  match @server.get_string(Json::string("not an object"), "name") {
    Err(result) => {
      @debug.assert_eq(result.is_error, Some(true))
      match result.content[0] {
        Text(msg, ..) => assert_true(msg.contains("Expected JSON object"))
        _ => panic()
      }
    }
    Ok(_) => panic()
  }
}

///|
test "get_number extracts, rejects missing/wrong-type" {
  match @server.get_number(Json::object({ "count": 42.5 }), "count") {
    Ok(num) => @debug.assert_eq(num, 42.5)
    Err(_) => panic()
  }
  match @server.get_number(Json::object({ "other": 1.0 }), "count") {
    Err(result) => @debug.assert_eq(result.is_error, Some(true))
    Ok(_) => panic()
  }
  match @server.get_number(Json::object({ "count": "42" }), "count") {
    Err(result) => @debug.assert_eq(result.is_error, Some(true))
    Ok(_) => panic()
  }
}

///|
test "get_optional_string extracts, maps null/missing to None, rejects wrong-type" {
  match
    @server.get_optional_string(Json::object({ "value": "present" }), "value") {
    Ok(Some(value)) => @debug.assert_eq(value, "present")
    _ => panic()
  }
  match
    @server.get_optional_string(
      Json::object({ "value": Json::null() }),
      "value",
    ) {
    Ok(None) => ()
    _ => panic()
  }
  match
    @server.get_optional_string(Json::object({ "other": "value" }), "value") {
    Ok(None) => ()
    _ => panic()
  }
  match @server.get_optional_string(Json::object({ "value": 42.0 }), "value") {
    Err(result) => @debug.assert_eq(result.is_error, Some(true))
    Ok(_) => panic()
  }
}

///| =====================================================

///| Example: Complete Tool Implementation

///|
/// =====================================================
struct EchoTool {}

///|
impl Tool for EchoTool with fn name(_self : EchoTool) -> String {
  "echo"
}

///|
impl Tool for EchoTool with fn description(_self : EchoTool) -> String {
  "Echo back the input text"
}

///|
impl Tool for EchoTool with fn params(_self : EchoTool) -> Array[
  @server.ParamDef,
] {
  [
    {
      name: "text",
      description: "Text to echo back",
      type_: "string",
      required: true,
    },
  ]
}

///|
impl Tool for EchoTool with fn execute(_self : EchoTool, _context, args : Json) -> @server.ToolCallOutcome {
  let text = match @server.get_string(args, "text") {
    Ok(t) => t
    Err(err) => return Complete(err)
  }
  Complete(@server.ToolResult::text("Echo: " + text))
}

///|
#cfg(not(target="wasm-gc"))
async test "example: complete tool implementation with EchoTool" {
  let tool = EchoTool::{ }
  @debug.assert_eq(@tool.Tool::name(tool), "echo")
  @debug.assert_eq(@tool.Tool::description(tool), "Echo back the input text")

  // Test execution
  let args = Json::object({ "text": "Hello, MCP!" })
  let result = @tool.Tool::execute(
    tool,
    @runtime.RequestContext::new(@types.RequestId::Int(1)),
    args,
  )
  match result {
    Complete(tool_result) => {
      @debug.assert_eq(tool_result.is_error, Some(false))
      match tool_result.content[0] {
        Text(msg, ..) => @debug.assert_eq(msg, "Echo: Hello, MCP!")
        _ => panic()
      }
    }
    _ => panic()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "example: tool with error handling" {
  let tool = EchoTool::{ }

  // Missing argument
  let args = Json::object({})
  let result = @tool.Tool::execute(
    tool,
    @runtime.RequestContext::new(@types.RequestId::Int(1)),
    args,
  )
  match result {
    Complete(tool_result) => {
      @debug.assert_eq(tool_result.is_error, Some(true))
      match tool_result.content[0] {
        Text(msg, ..) => assert_true(msg.contains("Missing required field"))
        _ => panic()
      }
    }
    _ => panic()
  }
}
