///|
using @mcp {
  trait Tool,
  type ParamDef,
  type ToolResult,
  type ContentItem,
  string_param,
  number_param,
  optional_number_param,
  optional_string_param,
  get_number,
  get_string,
  get_optional_string,
  get_optional_number,
}

///|
pub(all) struct EchoTool {}

///|
pub impl Tool for EchoTool with name(_) -> String {
  "echo"
}

///|
pub impl Tool for EchoTool with description(_) -> String {
  "Echo back the input text. Useful for testing MCP connectivity."
}

///|
pub impl Tool for EchoTool with params(_) -> Array[ParamDef] {
  [string_param("text", "The text to echo back")]
}

///|
pub impl Tool for EchoTool with execute(_, args : Json) -> ToolResult {
  match get_string(args, "text") {
    Ok(text) => ToolResult::text(text)
    Err(result) => result
  }
}

///|
/// Tool: Calculate
/// Demonstrates: Number parsing, error handling, multiple operations
pub(all) struct CalculateTool {}

///|
pub impl Tool for CalculateTool with name(_self : CalculateTool) -> String {
  "calculate"
}

///|
pub impl Tool for CalculateTool with description(_self : CalculateTool) -> String {
  "Perform arithmetic operations: add, sub, mul, div, pow, sqrt"
}

///|
pub impl Tool for CalculateTool with params(_self : CalculateTool) -> Array[
  ParamDef,
] {
  [
    string_param("operation", "Operation: add, sub, mul, div, pow, sqrt"),
    number_param("a", "First operand"),
    optional_number_param("b", "Second operand (not needed for sqrt)"),
  ]
}

///|
pub impl Tool for CalculateTool with execute(_self : CalculateTool, args : Json) -> ToolResult {
  let op = match get_string(args, "operation") {
    Ok(o) => o
    Err(result) => return result
  }
  let a = match get_number(args, "a") {
    Ok(n) => n
    Err(result) => return result
  }
  let b_opt = match get_optional_number(args, "b") {
    Ok(n_opt) => n_opt
    Err(result) => return result
  }
  let result = match op {
    "add" => Ok(a + b_opt.unwrap_or(0.0))
    "sub" => Ok(a - b_opt.unwrap_or(0.0))
    "mul" => Ok(a * b_opt.unwrap_or(1.0))
    "div" => {
      let b = b_opt.unwrap_or(1.0)
      if b == 0.0 {
        Err("Division by zero")
      } else {
        Ok(a / b)
      }
    }
    "pow" => {
      let b = b_opt.unwrap_or(2.0)
      Ok(pow_float(a, b))
    }
    "sqrt" =>
      if a < 0.0 {
        Err("Cannot calculate square root of negative number")
      } else {
        Ok(sqrt_float(a))
      }
    _ => Err("Unknown operation: " + op)
  }
  match result {
    Ok(n) => ToolResult::text(n.to_string())
    Err(msg) => ToolResult::error(msg)
  }
}

///|
fn pow_float(base : Double, exp : Double) -> Double {
  if exp == 0.0 {
    1.0
  } else if exp < 0.0 {
    1.0 / pow_float(base, -exp)
  } else {
    let mut result = 1.0
    let mut count = exp
    while count > 0 {
      result = result * base
      count = count - 1
    }
    result
  }
}

///|
fn sqrt_float(n : Double) -> Double {
  if n < 0.0 {
    0.0
  } else if n == 0.0 {
    0.0
  } else {
    let mut x = n
    let epsilon = 1.0e-15
    while (x * x - n).abs() > epsilon {
      x = (x + n / x) / 2.0
    }
    x
  }
}

///|
/// Tool: Transform Text
/// Demonstrates: String manipulation, multiple operation types
pub(all) struct TransformTextTool {}

///|
pub impl Tool for TransformTextTool with name(_self : TransformTextTool) -> String {
  "transform_text"
}

///|
pub impl Tool for TransformTextTool with description(_self : TransformTextTool) -> String {
  "Transform text: uppercase, lowercase, reverse"
}

///|
pub impl Tool for TransformTextTool with params(_self : TransformTextTool) -> Array[
  ParamDef,
] {
  [
    string_param("text", "The text to transform"),
    string_param("operation", "Transformation: uppercase, lowercase, reverse"),
  ]
}

///|
pub impl Tool for TransformTextTool with execute(
  _self : TransformTextTool,
  args : Json,
) -> ToolResult {
  let text = match get_string(args, "text") {
    Ok(t) => t
    Err(result) => return result
  }
  let op = match get_string(args, "operation") {
    Ok(o) => o
    Err(result) => return result
  }
  let result = match op {
    "uppercase" => text.to_upper()
    "lowercase" => text.to_lower()
    "reverse" => {
      let chars = text.to_array()
      let mut reversed = ""
      let mut i = chars.length() - 1
      while i >= 0 {
        reversed = reversed + chars[i].to_string()
        i = i - 1
      }
      reversed
    }
    _ => return ToolResult::error("Unknown operation: " + op)
  }
  ToolResult::text(result)
}

///|
/// Tool: Analyze Text
/// Demonstrates: Multiple content items, optional parameters
pub(all) struct AnalyzeTextTool {}

///|
pub impl Tool for AnalyzeTextTool with name(_self : AnalyzeTextTool) -> String {
  "analyze_text"
}

///|
pub impl Tool for AnalyzeTextTool with description(_self : AnalyzeTextTool) -> String {
  "Analyze text and return word count, character count, and line count"
}

///|
pub impl Tool for AnalyzeTextTool with params(_self : AnalyzeTextTool) -> Array[
  ParamDef,
] {
  [
    string_param("text", "The text to analyze"),
    optional_string_param(
      "metrics", "Comma-separated: words,chars,lines (default: all)",
    ),
  ]
}

///|
pub impl Tool for AnalyzeTextTool with execute(
  _self : AnalyzeTextTool,
  args : Json,
) -> ToolResult {
  let text = match get_string(args, "text") {
    Ok(t) => t
    Err(result) => return result
  }
  let metrics_str = match get_optional_string(args, "metrics") {
    Ok(Some(m)) => m
    Ok(None) => "words,chars,lines"
    Err(result) => return result
  }
  let metrics = metrics_str.split(",")
  let results : Array[ContentItem] = []
  let should_check = fn(metric : String) -> Bool {
    for m in metrics {
      if m.trim() == metric {
        return true
      }
    }
    false
  }
  if should_check("words") {
    let wc = word_count(text)
    results.push(ContentItem::Text("Words: " + wc.to_string()))
  }
  if should_check("chars") {
    let cc = text.length()
    results.push(ContentItem::Text("Characters: " + cc.to_string()))
  }
  if should_check("lines") {
    let lc = line_count(text)
    results.push(ContentItem::Text("Lines: " + lc.to_string()))
  }
  ToolResult::success(results)
}

///|
fn word_count(text : String) -> Int {
  let trimmed = text.trim()
  if trimmed.length() == 0 {
    0
  } else {
    let mut count = 0
    let mut in_word = false
    for c in trimmed.to_array() {
      if c == ' ' || c == '\n' || c == '\t' {
        in_word = false
      } else if not(in_word) {
        count = count + 1
        in_word = true
      }
    }
    count
  }
}

///|
fn line_count(text : String) -> Int {
  if text.length() == 0 {
    0
  } else {
    let mut count = 1
    for c in text.to_array() {
      if c == '\n' {
        count = count + 1
      }
    }
    count
  }
}

///|
/// Tool: Get Timestamp
/// Demonstrates: No parameters, multiple outputs
pub(all) struct GetTimestampTool {}

///|
pub impl Tool for GetTimestampTool with name(_self : GetTimestampTool) -> String {
  "get_timestamp"
}

///|
pub impl Tool for GetTimestampTool with description(_self : GetTimestampTool) -> String {
  "Get current timestamp in multiple formats"
}

///|
pub impl Tool for GetTimestampTool with params(_self : GetTimestampTool) -> Array[
  ParamDef,
] {
  []
}

///|
pub impl Tool for GetTimestampTool with execute(
  _self : GetTimestampTool,
  _args : Json,
) -> ToolResult {
  let content = [
    ContentItem::Text("Unix epoch (ms): 1704067200000"),
    ContentItem::Text("ISO 8601: 2024-01-01T00:00:00Z"),
  ]
  ToolResult::success(content)
}
