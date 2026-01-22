///| =====================================================
///| Tool Trait Unit Tests
///| Comprehensive tests for Tool trait and ToolResult
///| =====================================================

///| =====================================================
///| ToolResult Constructor Tests
///| =====================================================

test "ToolResult::text creates single text content" {
  let result = ToolResult::text("Success")
  assert_eq(result.is_error, false)
  assert_eq(result.content.length(), 1)
  match result.content[0] {
    Text(msg) => assert_eq(msg, "Success")
    _ => panic()
  }
}

test "ToolResult::error creates error result" {
  let result = ToolResult::error("Failed")
  assert_eq(result.is_error, true)
  assert_eq(result.content.length(), 1)
  match result.content[0] {
    Text(msg) => assert_eq(msg, "Failed")
    _ => panic()
  }
}

test "ToolResult::success with multiple content items" {
  let items = [
    ContentItem::Text("Line 1"),
    ContentItem::Text("Line 2"),
    ContentItem::Image("base64data", mime_type="image/png"),
  ]
  let result = ToolResult::success(items)
  assert_eq(result.is_error, false)
  assert_eq(result.content.length(), 3)
}

test "ToolResult::success with empty array" {
  let items: Array[ContentItem] = []
  let result = ToolResult::success(items)
  assert_eq(result.is_error, false)
  assert_eq(result.content.length(), 0)
}

///| =====================================================
///| ContentItem Tests
///| =====================================================

test "ContentItem::Text with multiline content" {
  let text = "Line 1\nLine 2\nLine 3"
  let item = ContentItem::Text(text)
  match item {
    Text(content) => assert_eq(content, text)
    _ => panic()
  }
}

test "ContentItem::Image with different MIME types" {
  let png = ContentItem::Image("data", mime_type="image/png")
  let jpeg = ContentItem::Image("data", mime_type="image/jpeg")

  match png {
    Image(data, mime_type~) => {
      assert_eq(data, "data")
      assert_eq(mime_type, "image/png")
    }
    _ => panic()
  }

  match jpeg {
    Image(_, mime_type~) => assert_eq(mime_type, "image/jpeg")
    _ => panic()
  }
}

test "ContentItem::Resource with URI" {
  let uri = "file:///path/to/resource.txt"
  let item = ContentItem::Resource(uri)
  match item {
    Resource(u) => assert_eq(u, uri)
    _ => panic()
  }
}

test "ContentItem derive Eq and Show" {
  let text1 = ContentItem::Text("Hello")
  let text2 = ContentItem::Text("Hello")
  let text3 = ContentItem::Text("World")

  // Test Eq
  assert_eq(text1, text2)
  assert_true(text1 != text3)

  // Test Show
  assert_eq(text1.to_string(), "Text(\"Hello\")")
}

///| =====================================================
///| Helper Function Tests
///| =====================================================

test "get_string extracts valid string field" {
  let json = Json::object({
    "name": Json::string("MoonBit"),
  })
  match get_string(json, "name") {
    Ok(name) => assert_eq(name, "MoonBit")
    Err(_) => panic()
  }
}

test "get_string returns error for missing field" {
  let json = Json::object({ "other": Json::string("value") })
  match get_string(json, "name") {
    Err(result) => assert_eq(result.is_error, true)
    Ok(_) => panic()
  }
}

test "get_string returns error for wrong type" {
  let json = Json::object({ "name": Json::number(42.0) })
  match get_string(json, "name") {
    Err(result) => {
      assert_eq(result.is_error, true)
      match result.content[0] {
        Text(msg) => assert_true(msg.contains("not a string"))
        _ => panic()
      }
    }
    Ok(_) => panic()
  }
}

test "get_string returns error for non-object" {
  let json = Json::string("not an object")
  match get_string(json, "name") {
    Err(result) => {
      assert_eq(result.is_error, true)
      match result.content[0] {
        Text(msg) => assert_true(msg.contains("Expected JSON object"))
        _ => panic()
      }
    }
    Ok(_) => panic()
  }
}

test "get_number extracts valid number field" {
  let json = Json::object({
    "count": Json::number(42.5),
  })
  match get_number(json, "count") {
    Ok(num) => assert_eq(num, 42.5)
    Err(_) => panic()
  }
}

test "get_number returns error for missing field" {
  let json = Json::object({ "other": Json::number(1.0) })
  match get_number(json, "count") {
    Err(result) => assert_eq(result.is_error, true)
    Ok(_) => panic()
  }
}

test "get_number returns error for wrong type" {
  let json = Json::object({ "count": Json::string("42") })
  match get_number(json, "count") {
    Err(result) => assert_eq(result.is_error, true)
    Ok(_) => panic()
  }
}

test "get_optional_string returns Some for present field" {
  let json = Json::object({ "value": Json::string("present") })
  match get_optional_string(json, "value") {
    Ok(Some(value)) => assert_eq(value, "present")
    _ => panic()
  }
}

test "get_optional_string returns None for explicit null" {
  let json = Json::object({ "value": Json::null() })
  match get_optional_string(json, "value") {
    Ok(None) => ()
    _ => panic()
  }
}

test "get_optional_string returns None for missing field" {
  let json = Json::object({ "other": Json::string("value") })
  match get_optional_string(json, "value") {
    Ok(None) => ()
    _ => panic()
  }
}

test "get_optional_string returns error for wrong type" {
  let json = Json::object({ "value": Json::number(42.0) })
  match get_optional_string(json, "value") {
    Err(result) => assert_eq(result.is_error, true)
    Ok(_) => panic()
  }
}

///| =====================================================
///| Example: Complete Tool Implementation
///| =====================================================

struct EchoTool {}

impl Tool for EchoTool with name(_self : EchoTool) -> String {
  "echo"
}

impl Tool for EchoTool with description(_self : EchoTool) -> String {
  "Echo back the input text"
}

impl Tool for EchoTool with params(_self : EchoTool) -> Array[ParamDef] {
  [string_param("text", "Text to echo back")]
}

impl Tool for EchoTool with execute(_self : EchoTool, args : Json) -> ToolResult {
  let text = match get_string(args, "text") {
    Ok(t) => t
    Err(err) => return err
  }
  ToolResult::text("Echo: " + text)
}

async test "example: complete tool implementation with EchoTool" {
  let tool = EchoTool::{}
  assert_eq(tool.name(), "echo")
  assert_eq(tool.description(), "Echo back the input text")

  // Test execution
  let args = Json::object({
    "text": Json::string("Hello, MCP!"),
  })
  let result = tool.execute(args)
  assert_eq(result.is_error, false)
  match result.content[0] {
    Text(msg) => assert_eq(msg, "Echo: Hello, MCP!")
    _ => panic()
  }
}

async test "example: tool with error handling" {
  let tool = EchoTool::{}

  // Missing argument
  let args = Json::object({})
  let result = tool.execute(args)
  assert_eq(result.is_error, true)
  match result.content[0] {
    Text(msg) => assert_true(msg.contains("Missing required field"))
    _ => panic()
  }
}
