///|
struct EchoTool {}

///|
impl @mcp.Tool for EchoTool with fn name(_) -> String {
  "echo"
}

///|
impl @mcp.Tool for EchoTool with fn description(_) -> String {
  "Echo back the input text"
}

///|
impl @mcp.Tool for EchoTool with fn params(_) -> Array[@mcp.ParamDef] {
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
impl @mcp.Tool for EchoTool with fn execute(_, args : Json) -> @mcp.ToolCallOutcome {
  match @mcp.get_string(args, "text") {
    Ok(text) =>
      @mcp.ToolCallOutcome::Complete(@mcp.ToolResult::text("Echo: \{text}"))
    Err(_) =>
      @mcp.ToolCallOutcome::Complete(
        @mcp.ToolResult::error("Missing 'text' parameter"),
      )
  }
}

///|
struct AddTool {}

///|
impl @mcp.Tool for AddTool with fn name(_) -> String {
  "add"
}

///|
impl @mcp.Tool for AddTool with fn description(_) -> String {
  "Add two numbers together"
}

///|
impl @mcp.Tool for AddTool with fn params(_) -> Array[@mcp.ParamDef] {
  [
    { name: "a", description: "First number", type_: "number", required: true, },
    {
      name: "b",
      description: "Second number",
      type_: "number",
      required: true,
    },
  ]
}

///|
impl @mcp.Tool for AddTool with fn execute(_, args : Json) -> @mcp.ToolCallOutcome {
  let a = match @mcp.get_number(args, "a") {
    Ok(n) => n
    Err(_) =>
      return @mcp.ToolCallOutcome::Complete(
        @mcp.ToolResult::error("Missing 'a' parameter"),
      )
  }
  let b = match @mcp.get_number(args, "b") {
    Ok(n) => n
    Err(_) =>
      return @mcp.ToolCallOutcome::Complete(
        @mcp.ToolResult::error("Missing 'b' parameter"),
      )
  }
  @mcp.ToolCallOutcome::Complete(
    @mcp.ToolResult::text("\{a} + \{b} = \{a + b}"),
  )
}

///|
async fn main {
  let server = @mcp.mcp_server(name="example-server", version="1.0.0")
    .with_tool(EchoTool::{ })
    .with_tool(AddTool::{ })
  server.run_stdio()
}
