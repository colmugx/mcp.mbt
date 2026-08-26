///| Tool Trait Unit Tests

///| Comprehensive tests for Tool trait and ToolResult

///|
/// ToolResult Constructor Tests
test "ToolResult::text creates single text content" {
  let result = ToolResult::text("Success")
  @debug.assert_eq(result.is_error, false)
  @debug.assert_eq(result.content.length(), 1)
  match result.content[0] {
    Text(msg) => @debug.assert_eq(msg, "Success")
    _ => panic()
  }
}

///|
test "ToolResult::error creates error result" {
  let result = ToolResult::error("Failed")
  @debug.assert_eq(result.is_error, true)
  @debug.assert_eq(result.content.length(), 1)
  match result.content[0] {
    Text(msg) => @debug.assert_eq(msg, "Failed")
    _ => panic()
  }
}

///|
test "ToolResult::success with multiple content items" {
  let items = [
    ContentItem::Text("Line 1"),
    ContentItem::Text("Line 2"),
    ContentItem::Image("base64data", mime_type="image/png"),
  ]
  let result = ToolResult::success(items)
  @debug.assert_eq(result.is_error, false)
  @debug.assert_eq(result.content.length(), 3)
}

///|
test "ToolResult::success with empty array" {
  let items : Array[ContentItem] = []
  let result = ToolResult::success(items)
  @debug.assert_eq(result.is_error, false)
  @debug.assert_eq(result.content.length(), 0)
}

///|
/// ContentItem Tests
test "ContentItem::Text with multiline content" {
  let text = "Line 1\nLine 2\nLine 3"
  let item = ContentItem::Text(text)
  match item {
    Text(content) => @debug.assert_eq(content, text)
    _ => panic()
  }
}

///|
test "ContentItem::Image with different MIME types" {
  let png = ContentItem::Image("data", mime_type="image/png")
  let jpeg = ContentItem::Image("data", mime_type="image/jpeg")
  match png {
    Image(data, mime_type~) => {
      @debug.assert_eq(data, "data")
      @debug.assert_eq(mime_type, "image/png")
    }
    _ => panic()
  }
  match jpeg {
    Image(_, mime_type~) => @debug.assert_eq(mime_type, "image/jpeg")
    _ => panic()
  }
}

///|
test "ContentItem::ResourceLink with URI" {
  let uri = "file:///path/to/resource.txt"
  let item = ContentItem::ResourceLink(uri)
  match item {
    ResourceLink(u) => @debug.assert_eq(u, uri)
    _ => panic()
  }
}

///|
test "ContentItem derive Eq and Show" {
  let text1 = ContentItem::Text("Hello")
  let text2 = ContentItem::Text("Hello")
  let text3 = ContentItem::Text("World")
  @debug.assert_eq(text1, text2)
  assert_true(text1 != text3)
  @debug.assert_eq(@debug.to_string(text1), "Text(\"Hello\")")
}

///|
/// Helper Function Tests
test "get_string extracts valid string field" {
  let json = Json::object({ "name": "MoonBit" })
  match get_string(json, "name") {
    Ok(name) => @debug.assert_eq(name, "MoonBit")
    Err(_) => panic()
  }
}

///|
test "get_string returns error for missing field" {
  let json = Json::object({ "other": "value" })
  match get_string(json, "name") {
    Err(result) => @debug.assert_eq(result.is_error, true)
    Ok(_) => panic()
  }
}

///|
test "get_string returns error for wrong type" {
  let json = Json::object({ "name": 42.0 })
  match get_string(json, "name") {
    Err(result) => {
      @debug.assert_eq(result.is_error, true)
      match result.content[0] {
        Text(msg) => assert_true(msg.contains("not a string"))
        _ => panic()
      }
    }
    Ok(_) => panic()
  }
}

///|
test "get_string returns error for non-object" {
  let json = Json::string("not an object")
  match get_string(json, "name") {
    Err(result) => {
      @debug.assert_eq(result.is_error, true)
      match result.content[0] {
        Text(msg) => assert_true(msg.contains("Expected JSON object"))
        _ => panic()
      }
    }
    Ok(_) => panic()
  }
}

///|
test "get_number extracts valid number field" {
  let json = Json::object({ "count": 42.5 })
  match get_number(json, "count") {
    Ok(num) => @debug.assert_eq(num, 42.5)
    Err(_) => panic()
  }
}

///|
test "get_number returns error for missing field" {
  let json = Json::object({ "other": 1.0 })
  match get_number(json, "count") {
    Err(result) => @debug.assert_eq(result.is_error, true)
    Ok(_) => panic()
  }
}

///|
test "get_number returns error for wrong type" {
  let json = Json::object({ "count": "42" })
  match get_number(json, "count") {
    Err(result) => @debug.assert_eq(result.is_error, true)
    Ok(_) => panic()
  }
}

///|
test "get_optional_string returns Some for present field" {
  let json = Json::object({ "value": "present" })
  match get_optional_string(json, "value") {
    Ok(Some(value)) => @debug.assert_eq(value, "present")
    _ => panic()
  }
}

///|
test "get_optional_string returns None for explicit null" {
  let json = Json::object({ "value": Json::null() })
  match get_optional_string(json, "value") {
    Ok(None) => ()
    _ => panic()
  }
}

///|
test "get_optional_string returns None for missing field" {
  let json = Json::object({ "other": "value" })
  match get_optional_string(json, "value") {
    Ok(None) => ()
    _ => panic()
  }
}

///|
test "get_optional_string returns error for wrong type" {
  let json = Json::object({ "value": 42.0 })
  match get_optional_string(json, "value") {
    Err(result) => @debug.assert_eq(result.is_error, true)
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
impl Tool for EchoTool with fn params(_self : EchoTool) -> Array[ParamDef] {
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
impl Tool for EchoTool with fn execute(_self : EchoTool, args : Json) -> ToolCallOutcome {
  let text = match get_string(args, "text") {
    Ok(t) => t
    Err(err) => return Complete(err)
  }
  Complete(ToolResult::text("Echo: " + text))
}

///|
#cfg(not(target="wasm-gc"))
async test "example: complete tool implementation with EchoTool" {
  let tool = EchoTool::{  }
  @debug.assert_eq(@tool.Tool::name(tool), "echo")
  @debug.assert_eq(@tool.Tool::description(tool), "Echo back the input text")

  // Test execution
  let args = Json::object({ "text": "Hello, MCP!" })
  let result = @tool.Tool::execute(tool, args)
  match result {
    Complete(tool_result) => {
      @debug.assert_eq(tool_result.is_error, false)
      match tool_result.content[0] {
        Text(msg) => @debug.assert_eq(msg, "Echo: Hello, MCP!")
        _ => panic()
      }
    }
    _ => panic()
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "example: tool with error handling" {
  let tool = EchoTool::{  }

  // Missing argument
  let args = Json::object({})
  let result = @tool.Tool::execute(tool, args)
  match result {
    Complete(tool_result) => {
      @debug.assert_eq(tool_result.is_error, true)
      match tool_result.content[0] {
        Text(msg) => assert_true(msg.contains("Missing required field"))
        _ => panic()
      }
    }
    _ => panic()
  }
}
