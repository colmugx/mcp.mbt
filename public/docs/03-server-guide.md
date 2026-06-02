# 3. Server 开发指南

## 3.1 创建 Server

```moonbit
let server = mcp_server(name="my-server", version="1.0.0")
```

或使用完整构造：

```moonbit
let server = MCPServer::new("my-server", "1.0.0")
```

## 3.2 注册 Tool

### 方式一：直接注册

```moonbit
server.register_tool(
  "get_weather",                                    // 工具名
  "Get current weather for a city",                 // 描述
  Json::object({                                    // Input Schema
    "type": Json::string("object"),
    "properties": Json::object({
      "city": Json::object({
        "type": Json::string("string"),
        "description": Json::string("City name"),
      }),
    }),
    "required": Json::array([Json::string("city")]),
  }),
  async fn(args : Json) -> Result[ToolResult, MCPError] {
    let city = match args {
      Object(obj) => match obj.get("city") {
        Some(String(s)) => s
        _ => return Err(InvalidParams("Missing 'city' parameter"))
      }
      _ => return Err(InvalidParams("Expected object"))
    }
    Ok(ToolResult::text("Weather in \{city}: Sunny, 22°C"))
  },
)
```

### 方式二：使用 `get_string` 等工具函数

```moonbit
server.register_tool(
  "echo",
  "Echo back the input",
  Json::object({
    "type": Json::string("object"),
    "properties": Json::object({
      "message": Json::object({
        "type": Json::string("string"),
      }),
    }),
  }),
  async fn(args : Json) -> Result[ToolResult, MCPError] {
    match get_string(args, "message") {
      Ok(msg) => Ok(ToolResult::text(msg))
      Err(result) => Ok(result) // get_string 返回 ToolResult 错误
    }
  },
)
```

可用的 JSON 提取函数：

| 函数 | 签名 | 说明 |
|------|------|------|
| `get_string` | `(Json, String) -> Result[String, ToolResult]` | 提取必需字符串 |
| `get_number` | `(Json, String) -> Result[Double, ToolResult]` | 提取必需数字 |
| `get_optional_string` | `(Json, String) -> Result[String?, ToolResult]` | 提取可选字符串 |
| `get_optional_number` | `(Json, String) -> Result[Double?, ToolResult]` | 提取可选数字 |

### 方式三：实现 Tool trait

```moonbit
struct WeatherTool {}

impl Tool for WeatherTool with name(_) -> String { "get_weather" }
impl Tool for WeatherTool with description(_) -> String {
  "Get current weather for a city"
}
impl Tool for WeatherTool with params(_) -> Array[ParamDef] {
  [
    ParamDef::{ name: "city", description: "City name", type_: "string", required: true },
  ]
}
impl Tool for WeatherTool with async execute(_, args : Json) -> ToolResult {
  match get_string(args, "city") {
    Ok(city) => ToolResult::text("Weather in \{city}: Sunny, 22°C")
    Err(result) => result
  }
}

// 注册
server.register_trait_tool(WeatherTool{})
```

### 方式四：使用 `tool_fn`（类型安全的函数式 API）

```moonbit
// 定义参数结构体
struct EchoArgs {
  message : String
} derive(Show)

// 实现 Params trait
impl Params for EchoArgs with schema() -> JsonSchema {
  obj_schema(
    Map::from_array([("message", str_schema("Message to echo"))]),
    ["message"],
  )
}
impl Params for EchoArgs with from_json(json : Json) -> EchoArgs raise ToolError {
  let msg = get_string(json, "message") catch { _ =>
    raise ToolError("Missing 'message' parameter")
  }
  { message: msg }
}
impl Params for EchoArgs with to_json(self : EchoArgs) -> Json {
  Json::object({ "message": Json::string(self.message) })
}

// 创建工具
let echo_tool = tool_fn(
  fn(args : EchoArgs) -> String { args.message },
  name="echo",
  description="Echo back the input",
)

server.register_trait_tool(echo_tool)
```

### 方式五：使用 `simple_tool`（无参数工具）

```moonbit
let ping_tool = simple_tool(
  "ping",
  "Simple ping tool",
  fn(_ : Json) -> ToolResult { ToolResult::text("pong") },
)
server.register_trait_tool(ping_tool)
```

### 方式六：链式 Builder API

```moonbit
let server = mcp_server(name="my-server", version="1.0.0")
  .with_tool(MyTool{})
  .with_resource(MyResource{})
  .with_prompt(MyPrompt{})
  .with_auth(AuthConfig::new(
    verify_token=fn(token) { validate(token) },
    resource_metadata_url="http://localhost:4240/mcp",
    authorization_servers=["https://auth.example.com"],
  ))
```

`with_auth()` 为 HTTP 模式配置 Bearer token 认证。详见 [Transport 参考手册](04-transport-reference.md#服务器端认证)。

## 3.3 ToolResult 构造

```moonbit
// 文本结果
ToolResult::text("Hello")

// 多内容项
ToolResult::success([
  Text("Here is the result:"),
  Image(base64_data, mime_type="image/png"),
  ResourceLink("file:///path/to/data.json"),
])

// 错误结果
ToolResult::error("Something went wrong")
```

### ToToolResult trait

`ToToolResult` trait 提供自动类型转换，以下类型已内置实现：

| 类型 | 转换行为 |
|------|----------|
| `String` | `ToolResult::text(self)` |
| `Int` | `ToolResult::text(self.to_string())` |
| `Bool` | `ToolResult::text(self.to_string())` |
| `Double` | `ToolResult::text(self.to_string())` |
| `ToolResult` | 直接返回（identity） |

在 `tool_fn` 中可以利用此 trait 让返回值自动转换为 `ToolResult`。

## 3.4 注册 Resource

```moonbit
server.register_resource(
  "file:///config.json",       // URI
  "config",                    // 名称
  "Application configuration", // 描述
  "application/json",          // MIME 类型
  async fn() -> Result[ResourceReadResult, MCPError] {
    Ok({
      uri: "file:///config.json",
      content: Text("{ \"theme\": \"dark\" }"),
    })
  },
)
```

或实现 Resource trait：

```moonbit
struct ConfigResource {}

impl Resource for ConfigResource with name(_) -> String { "config" }
impl Resource for ConfigResource with description(_) -> String {
  "Application configuration"
}
impl Resource for ConfigResource with uri(_) -> String {
  "file:///config.json"
}
impl Resource for ConfigResource with mime_type(_) -> String {
  "application/json"
}
impl Resource for ConfigResource with async read(_) -> Result[ResourceReadResult, MCPError] {
  Ok({
    uri: "file:///config.json",
    content: Text("{ \"theme\": \"dark\" }"),
  })
}

server.register_trait_resource(ConfigResource{})
```

ResourceContent 类型：

```moonbit
pub(all) enum ResourceContent {
  Text(String)                          // 文本内容
  Blob(String, mime_type~ : String)     // Base64 二进制内容
} derive(Eq, Show)
```

## 3.5 注册 Prompt

```moonbit
server.register_prompt(
  "code_review",                                   // 名称
  "Generate code review feedback",                  // 描述
  [
    { name: "code", description: Some("Code to review"), required: Some(true) },
  ],
  async fn(args : Json) -> Result[GetPromptResult, MCPError] {
    let code = match args {
      Object(obj) => match obj.get("code") {
        Some(String(s)) => s
        _ => ""
      }
      _ => ""
    }
    Ok({
      description: Some("Code review for submitted code"),
      messages: [
        { role: "user", content: Text("Please review this code:\n\{code}") },
      ],
    })
  },
)
```

或实现 Prompt trait：

```moonbit
impl Prompt for CodeReviewPrompt with name(_) -> String { "code_review" }
impl Prompt for CodeReviewPrompt with description(_) -> String {
  "Generate code review feedback"
}
impl Prompt for CodeReviewPrompt with arguments(_) -> Array[@types.PromptArgument] {
  [
    { name: "code", description: Some("Code to review"), required: Some(true) },
  ]
}
impl Prompt for CodeReviewPrompt with async get(_, args : Json) -> Result[GetPromptResult, MCPError] {
  // ...
}
```

## 3.6 发送通知

当 tool/resource/prompt 列表发生变化时，通知已连接的 client：

```moonbit
server.notify_tools_list_changed(transport)
server.notify_resources_list_changed(transport)
server.notify_prompts_list_changed(transport)
```

## 3.7 运行 Server

### STDIO 模式

```moonbit
async fn main {
  let server = mcp_server(name="my-server", version="1.0.0")
  // ... 注册 tool/resource/prompt ...
  server.run_stdio()
}
```

STDIO 模式通过 stdin 接收 JSON-RPC 请求，通过 stdout 返回响应。这是最常见的部署模式，与 Claude Desktop、VS Code 等 MCP host 兼容。

### HTTP 模式

```moonbit
async fn main {
  @async.with_task_group(fn(group) {
    let server = mcp_server(name="my-server", version="1.0.0")
    // ... 注册 ...
    server.run_http(port=4240, path="/mcp", group~)
  })
}
```

HTTP 模式启动 Streamable HTTP server：
- `POST /mcp` — 接收 JSON-RPC 请求，返回 JSON 或 SSE 响应
- `GET /mcp` — SSE 通知流（server 推送通知给 client）

### 自定义 Transport

```moonbit
async fn main {
  @async.with_task_group(fn(group) {
    let server = mcp_server(name="my-server", version="1.0.0")
    let transport = AnyTransport::Stdio(StdioTransport::new())
    server.run(transport, group)
  })
}
```

`run()` 方法接受任何 `AnyTransport` 实例和 `TaskGroup`。

## 3.8 Schema 构建

### 使用 SchemaBuilder

```moonbit
let schema = schema_builder()
  .field("query", str_type(), required=true, desc="Search query")
  .field("limit", int_type(), desc="Maximum results")
  .field("tags", arr_type(str_type()), desc="Filter tags")
  .build(desc="Search parameters")

let json = schema.to_json()
```

### 使用快捷函数

```moonbit
str_schema(desc="A string value")
int_schema(desc="An integer value")
num_schema(desc="A number value")
bool_schema(desc="A boolean value")
arr_schema(item_schema, desc="Array of items")
obj_schema(properties_map, required_fields, desc="Object schema")
```

### 使用 Params trait 自动生成 Schema

`Params` trait 已为以下类型提供实现：

- `String`, `Int`, `Double`, `Bool`
- `Array[T]`（当 `T` 也实现 `Params`）
- `T?`（当 `T` 也实现 `Params`）

通过 `tool_fn` 使用时，schema 自动从参数类型推导。
