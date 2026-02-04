# MCP.mbt 0.3.x → 0.4.x 迁移指南

## 概述

0.4 版本引入了**函数式 Pipeline DSL** 和 **struct-as-schema** 设计，使代码更加简洁、类型安全。

主要改进：
- **Pipeline 风格**：使用 `|>` 操作符链式构建服务器
- **struct 即 schema**：通过 `derive(Params)` 自动生成参数定义
- **类型安全**：工具 handler 直接接收类型化参数，无需手动解析 JSON
- **更少的样板代码**：减少重复的定义和转换逻辑

---

## 1. 服务器创建与运行

### 旧方式 (0.3.x)

```moonbit
let server = @mcp.MCPServer::new("my-server", "1.0.0")
// ... 注册工具
let transport = @mcp.AnyTransport::Stdio(@mcp.StdioTransport::new())
server.run(transport)
```

### 新方式 (0.4.x) - Pipeline 风格

```moonbit
@mcp.mcp_server(name="my-server", version="1.0.0")
|> register_tools(storage)
|> register_resources(storage)
|> register_prompts(storage)
|> fn(s) { s.run_stdio() }
```

或使用 HTTP：

```moonbit
let server = @mcp.mcp_server(name="my-server", version="1.0.0")
  |> register_tools(storage)

@async.with_task_group(async fn(group) {
  server.run_http(port=4042, group~)
})
```

---

## 2. 注册函数变更

### 旧方式

```moonbit
pub fn register_tools(server : @mcp.MCPServer, storage : Storage) -> Unit {
  server.register_trait_tool(CreateNoteTool::new(storage))
  server.register_trait_tool(ReadNoteTool::new(storage))
}
```

### 新方式

```moonbit
pub fn register_tools(
  server : @mcp.MCPServer,
  storage : Storage
) -> @mcp.MCPServer {
  server
  |> @mcp.MCPServer::with_tool(CreateNoteTool::new(storage))
  |> @mcp.MCPServer::with_tool(ReadNoteTool::new(storage))
}
```

**要点**：
- 返回类型从 `Unit` 改为 `@mcp.MCPServer`
- 使用 `with_tool` 替代 `register_trait_tool`
- 使用 `|>` pipeline 操作符

---

## 3. 工具定义（两种风格并存）

### 风格 A：传统 Trait 风格（仍然支持）

适合需要完全控制工具行为的场景。

```moonbit
pub(all) struct ReadNoteTool {
  storage : Storage
}

pub fn ReadNoteTool::new(storage : Storage) -> ReadNoteTool {
  { storage, }
}

pub impl @tool.Tool for ReadNoteTool with name(_self) -> String {
  "read_note"
}

pub impl @tool.Tool for ReadNoteTool with description(_self) -> String {
  "Read a note by title"
}

// 参数定义改为直接构造
pub impl @tool.Tool for ReadNoteTool with params(_self) -> Array[@tool.ParamDef] {
  [
    {
      name: "title",
      description: "Note title to read (required)",
      type_: "string",
      required: true,
    },
  ]
}

pub impl @tool.Tool for ReadNoteTool with execute(_self, args) {
  // 手动解析 JSON
  let title = match get_string(args, "title") {
    Some(t) => t
    None => return @tool.ToolResult::error("Missing 'title'")
  }
  // ... 执行逻辑
}
```

### 风格 B：函数式风格（推荐）

适合简单的 CRUD 操作，代码更简洁。

```moonbit
/// 1. 定义参数结构体
struct CreateNoteParams {
  title : String
  content : String
  tags : Array[String]?
} derive(ToJson, FromJson)

/// 2. 实现 Params trait（定义 schema）
pub impl @core.Params for CreateNoteParams with schema() -> @core.JsonSchema {
  @core.obj_schema(
    {
      "title": @core.str_schema(desc="Note title (required)"),
      "content": @core.str_schema(desc="Note content (required)"),
      "tags": @core.arr_schema(@core.str_schema(), desc="Optional tags"),
    },
    ["title", "content"],  // required fields
    desc="Create a new note",
  )
}

pub impl @core.Params for CreateNoteParams with from_json(j : Json) -> CreateNoteParams raise @core.ToolError {
  match CreateNoteParams::from_json(j) {
    Ok(v) => v
    Err(_) => raise @core.ToolError("Failed to parse params")
  }
}

pub impl @core.Params for CreateNoteParams with to_json(self : CreateNoteParams) -> Json {
  self.to_json()
}

/// 3. 使用 tool_fn 创建工具
pub fn create_note_tool(storage : Storage) -> @core.ToolWrapper {
  @core.tool_fn(
    name="create_note",
    description="Create a new note with title, content, and optional tags",
    handler=fn(params : CreateNoteParams) -> String {
      // 直接接收类型化参数，无需手动解析 JSON！
      let note : Note = {
        title: params.title,
        content: params.content,
        tags: params.tags.or([]),
      }
      match storage.save_note(note) {
        Ok(_) => "✅ Note created: \{params.title}"
        Err(msg) => "Failed: \{msg}"
      }
    },
  )
}

/// 4. 注册
pub fn register_tools(server : @mcp.MCPServer, storage : Storage) -> @mcp.MCPServer {
  server
  |> @mcp.MCPServer::with_tool(create_note_tool(storage))
}
```

---

## 4. 参数定义变更

### 旧方式（已废弃）

```moonbit
// 这些 helper 函数已被移至 deprecated.mbt
[
  @mcp.string_param("title", "Note title"),
  @mcp.number_param("count", "Item count"),
  @mcp.boolean_param("active", "Is active"),
  @mcp.optional_string_param("description", "Optional description"),
]
```

### 新方式 A：直接构造 ParamDef

```moonbit
[
  { name: "title", description: "Note title", type_: "string", required: true },
  { name: "count", description: "Item count", type_: "number", required: true },
  { name: "active", description: "Is active", type_: "boolean", required: true },
  { name: "description", description: "Optional description", type_: "string", required: false },
]
```

### 新方式 B：struct-as-schema（推荐）

```moonbit
struct MyParams {
  title : String
  count : Int
  active : Bool
  description : String?  // Optional 自动标记为 required: false
} derive(ToJson, FromJson)

pub impl @core.Params for MyParams with schema() -> @core.JsonSchema {
  @core.obj_schema(
    {
      "title": @core.str_schema(desc="Note title"),
      "count": @core.int_schema(desc="Item count"),
      "active": @core.bool_schema(desc="Is active"),
      "description": @core.str_schema(desc="Optional description"),
    },
    ["title", "count", "active"],  // description 不在 required 中
    desc="My tool description",
  )
}
```

**类型字段对照表**：

| 类型 | type_ 值 |
|------|---------|
| String | `"string"` |
| Int | `"integer"` |
| Double | `"number"` |
| Bool | `"boolean"` |
| Array[T] | `"array"` |
| 对象 | `"object"` |

---

## 5. 资源注册

### 旧方式

```moonbit
pub fn register_resources(server : @mcp.MCPServer, _storage : Storage) -> Unit {
  server.register_trait_resource(WeatherResource::new("New York"))
  server.register_trait_resource(WeatherResource::new("London"))
}
```

### 新方式

```moonbit
pub fn register_resources(
  server : @mcp.MCPServer,
  _storage : Storage
) -> @mcp.MCPServer {
  server
  |> s => { s.with_resource(WeatherResource::new("New York")) }
  |> s => { s.with_resource(WeatherResource::new("London")) }
}
```

---

## 6. 提示注册

### 旧方式

```moonbit
pub fn register_prompts(server : @mcp.MCPServer, storage : Storage) -> Unit {
  server.register_trait_prompt(SummarizeNotePrompt::{ storage, })
}
```

### 新方式

```moonbit
pub fn register_prompts(
  server : @mcp.MCPServer,
  storage : Storage
) -> @mcp.MCPServer {
  server.with_prompt(SummarizeNotePrompt::{ storage, })
}
```

---

## 7. 完整示例对比

### 0.3.x 完整示例

```moonbit
// main.mbt
async fn main {
  println("Starting server...")
  let storage = @internal.Storage::new("notes")

  let server = @mcp.MCPServer::new("moon-notes", "1.0.0")
  @internal.register_tools(server, storage)
  @internal.register_resources(server, storage)
  @internal.register_prompts(server, storage)

  let transport = @mcp.AnyTransport::Stdio(@mcp.StdioTransport::new())
  server.run(transport) catch {
    e => println("Server error: \{e}")
  }
}

// tools.mbt
pub fn register_tools(server : @mcp.MCPServer, storage : Storage) -> Unit {
  server.register_trait_tool(CreateNoteTool::new(storage))
  server.register_trait_tool(ReadNoteTool::new(storage))
}

pub impl @tool.Tool for CreateNoteTool with params(_self) -> Array[@tool.ParamDef] {
  [
    @mcp.string_param("title", "Note title"),
    @mcp.string_param("content", "Note content"),
  ]
}
```

### 0.4.x 完整示例

```moonbit
// main.mbt
async fn main {
  println("Starting server...")
  let storage = @internal.Storage::new("notes")

  @mcp.mcp_server(name="moon-notes", version="1.0.0")
  |> @internal.register_tools(storage)
  |> @internal.register_resources(storage)
  |> @internal.register_prompts(storage)
  |> fn(s) { s.run_stdio() }
}

// tools.mbt
pub fn register_tools(
  server : @mcp.MCPServer,
  storage : Storage
) -> @mcp.MCPServer {
  server
  |> @mcp.MCPServer::with_tool(CreateNoteTool::new(storage))
  |> @mcp.MCPServer::with_tool(ReadNoteTool::new(storage))
}

// 方式 A：传统风格
pub impl @tool.Tool for CreateNoteTool with params(_self) -> Array[@tool.ParamDef] {
  [
    { name: "title", description: "Note title", type_: "string", required: true },
    { name: "content", description: "Note content", type_: "string", required: true },
  ]
}

// 方式 B：函数式风格（推荐用于简单工具）
pub fn create_note_tool(storage : Storage) -> @core.ToolWrapper {
  @core.tool_fn(
    name="create_note",
    description="Create a note",
    handler=fn(params : CreateNoteParams) -> String {
      // 直接处理类型化参数
      "Created: \{params.title}"
    },
  )
}
```

---

## 8. 废弃 API 列表

以下 API 已被移至 `src/server/deprecated.mbt`，仍可使用但建议迁移：

| 废弃 API | 替代方案 |
|---------|---------|
| `@mcp.string_param(n, d)` | `{name: n, description: d, type_: "string", required: true}` |
| `@mcp.number_param(n, d)` | `{name: n, description: d, type_: "number", required: true}` |
| `@mcp.boolean_param(n, d)` | `{name: n, description: d, type_: "boolean", required: true}` |
| `@mcp.optional_string_param(n, d)` | `{name: n, description: d, type_: "string", required: false}` |
| `@mcp.optional_number_param(n, d)` | `{name: n, description: d, type_: "number", required: false}` |
| `@mcp.optional_boolean_param(n, d)` | `{name: n, description: d, type_: "boolean", required: false}` |
| `MCPServer::new(n, v)` | `mcp_server(name~, version~)` |
| `server.register_trait_tool(t)` | `server.with_tool(t)` |
| `server.register_trait_resource(r)` | `server.with_resource(r)` |
| `server.register_trait_prompt(p)` | `server.with_prompt(p)` |
| `server.run(transport)` | `server.run_stdio()` 或 `server.run_http(port~, group~)` |

---

## 9. 迁移检查清单

- [ ] 更新 `main.mbt`：使用 `mcp_server()` + pipeline
- [ ] 更新 `register_tools()`：返回 `@mcp.MCPServer`，使用 `with_tool`
- [ ] 更新 `register_resources()`：返回 `@mcp.MCPServer`，使用 `with_resource`
- [ ] 更新 `register_prompts()`：返回 `@mcp.MCPServer`，使用 `with_prompt`
- [ ] 更新 `ParamDef` 定义：从 helper 函数改为直接构造
- [ ] （可选）将简单工具迁移到 `tool_fn` 风格
- [ ] 删除 `AnyTransport` 和 `StdioTransport` 的手动创建
- [ ] 运行 `moon check` 验证
- [ ] 运行 `moon test` 确保测试通过

---

## 10. 新 API 核心类型

### JsonSchema 构造器

```moonbit
@core.str_schema(desc~)
@core.int_schema(desc~)
@core.num_schema(desc~)
@core.bool_schema(desc~)
@core.arr_schema(item, desc~)
@core.obj_schema(props, required, desc~)
```

### ToolWrapper

`tool_fn` 返回 `ToolWrapper`，它实现了 `Tool` trait，可以直接传给 `with_tool`。

```moonbit
pub fn tool_fn[Args : Params, Ret : ToToolResult](
  name~ : String,
  description~ : String,
  handler : (Args) -> Ret
) -> ToolWrapper
```

---

## 需要帮助？

查看示例代码：
- `examples/cmd/main/main.mbt` - 主入口
- `examples/internal/tools.mbt` - 工具定义（两种风格）
- `examples/internal/resources.mbt` - 资源注册
- `examples/internal/prompts.mbt` - 提示注册
