# MCP.mbt 0.3.x → 0.5.0 迁移指南

**版本**: 0.5.0  
**发布日期**: 2026-02-05  
**破坏性变更**: 是 (完全移除向后兼容代码)

---

## 📋 概述

0.5.0 是一个重大版本，包含三大核心改进：

1. **🚀 性能优化**: 8x 性能提升 + 并发请求处理
2. **✨ 开发体验**: SchemaBuilder 流式 API，减少样板代码
3. **🧹 代码清理**: 移除所有 deprecated API，代码库更简洁

**重要提示**: 
- 不再兼容 0.3.x API
- `deprecated.mbt` 已被完全删除
- 必须按此文档全量迁移

---

## 🎯 快速迁移路径

### 步骤概览

```
1. 更新依赖版本 → 2. 迁移服务器启动代码 → 3. 迁移工具定义 → 4. 测试验证
```

### 估计时间

| 项目规模 | 迁移时间 |
|---------|---------|
| 小型 (1-5 工具) | 30 分钟 |
| 中型 (6-20 工具) | 2 小时 |
| 大型 (20+ 工具) | 半天 |

---

## 1️⃣ 更新依赖

### moon.mod.json

```json
{
  "name": "your-project",
  "version": "1.0.0",
  "deps": {
    "colmugx/mcp": "0.5.0"
  }
}
```

### 安装依赖

```bash
moon install
moon check  # 查看编译错误
```

---

## 2️⃣ 服务器启动代码

### ❌ 旧代码 (0.3.x)

```moonbit
// main.mbt
async fn main {
  let storage = Storage::new("notes")
  let server = @mcp.MCPServer::new("my-server", "1.0.0")
  
  register_tools(server, storage)
  register_resources(server, storage)
  
  let transport = @mcp.AnyTransport::Stdio(@mcp.StdioTransport::new())
  server.run(transport) catch {
    e => @stdio.stderr.write("Error: " + e.to_string())
  }
}
```

### ✅ 新代码 (0.5.0)

```moonbit
// main.mbt
async fn main {
  let storage = Storage::new("notes")
  
  @mcp.mcp_server(name="my-server", version="1.0.0")
  |> register_tools(storage)
  |> register_resources(storage)
  |> fn(s) { s.run_stdio() }
}
```

**关键变更**:
- ❌ 移除 `MCPServer::new()` → ✅ 使用 `mcp_server()`
- ❌ 移除手动创建 `AnyTransport` → ✅ 使用 `run_stdio()`
- ✅ 使用 pipeline 风格 (`|>`)
- ✅ 并发处理已内置，无需手动配置

---

## 3️⃣ 工具注册

### ❌ 旧代码 (0.3.x)

```moonbit
pub fn register_tools(server : @mcp.MCPServer, storage : Storage) -> Unit {
  server.register_trait_tool(CreateNoteTool::new(storage))
  server.register_trait_tool(ReadNoteTool::new(storage))
}
```

### ✅ 新代码 (0.5.0)

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

**关键变更**:
- 返回类型: `Unit` → `@mcp.MCPServer`
- 方法名: `register_trait_tool` → `with_tool`
- 风格: 命令式 → Pipeline

同样适用于 Resource 和 Prompt：
- `register_trait_resource` → `with_resource`
- `register_trait_prompt` → `with_prompt`

---

## 4️⃣ 工具定义（两种风格）

### 风格 A: Trait 风格 (适合复杂工具)

#### ❌ 旧代码 (0.3.x)

```moonbit
pub impl @tool.Tool for ReadNoteTool with params(_self) -> Array[@tool.ParamDef] {
  [
    @mcp.string_param("title", "Note title to read"),
    @mcp.optional_string_param("format", "Output format"),
  ]
}
```

#### ✅ 新代码 (0.5.0)

```moonbit
pub impl @tool.Tool for ReadNoteTool with params(_self) -> Array[@tool.ParamDef] {
  [
    { name: "title", description: "Note title to read", type_: "string", required: true },
    { name: "format", description: "Output format", type_: "string", required: false },
  ]
}
```

**关键变更**:
- ❌ 移除所有 helper 函数 (`string_param`, `optional_string_param` 等)
- ✅ 直接构造 `ParamDef` 结构体

### 风格 B: 函数式风格 (推荐，适合简单工具)

#### 完整示例

```moonbit
///| 1. 定义参数结构体
struct CreateNoteParams {
  title : String
  content : String
  tags : Array[String]?
} derive(ToJson, FromJson)

///| 2. 实现 Params trait - schema() 方法
pub impl @core.Params for CreateNoteParams with schema() -> @core.JsonSchema {
  // 选项 A: 使用 Map 风格 (0.4.x 方式)
  @core.obj_schema(
    {
      "title": @core.str_schema(desc="Note title"),
      "content": @core.str_schema(desc="Note content"),
      "tags": @core.arr_schema(@core.str_schema(), desc="Optional tags"),
    },
    ["title", "content"],
    desc="Create a new note",
  )
  
  // 选项 B: 使用 SchemaBuilder (0.5.0 新增，推荐)
  @core.schema_builder()
    .field("title", @core.str_type(), required=true, desc="Note title")
    .field("content", @core.str_type(), required=true, desc="Note content")
    .field("tags", @core.arr_type(@core.str_type()), desc="Optional tags")
    .build(desc="Create a new note")
}

///| 3. 实现 Params trait - from_json() 方法
pub impl @core.Params for CreateNoteParams with from_json(j : Json) -> CreateNoteParams raise @core.ToolError {
  match CreateNoteParams::from_json(j) {
    Ok(v) => v
    Err(_) => raise @core.ToolError("Failed to parse CreateNoteParams")
  }
}

///| 4. 实现 Params trait - to_json() 方法
pub impl @core.Params for CreateNoteParams with to_json(self : CreateNoteParams) -> Json {
  self.to_json()
}

///| 5. 使用 tool_fn 创建工具
pub fn create_note_tool(storage : Storage) -> @core.ToolWrapper {
  @core.tool_fn(
    name="create_note",
    description="Create a new note with title, content, and optional tags",
    handler=fn(params : CreateNoteParams) -> String {
      // ✨ 直接接收类型化参数，无需手动解析 JSON！
      let note : Note = {
        title: params.title,
        content: params.content,
        tags: params.tags.or([]),
      }
      match storage.save_note(note) {
        Ok(_) => "✅ Note created: \{params.title}"
        Err(msg) => "❌ Failed: \{msg}"
      }
    },
  )
}

///| 6. 注册工具
pub fn register_tools(server : @mcp.MCPServer, storage : Storage) -> @mcp.MCPServer {
  server.with_tool(create_note_tool(storage))
}
```

---

## 5️⃣ SchemaBuilder API (0.5.0 新增)

### 类型构造器

```moonbit
@core.str_type()              // String
@core.int_type()              // Integer
@core.num_type()              // Number
@core.bool_type()             // Boolean
@core.arr_type(item_type)     // Array
@core.obj_type()              // Object
```

### 流式 API

```moonbit
@core.schema_builder()
  .field(name, type, required?, desc?)
  .field(name, type, required?, desc?)
  .build(desc?)
```

### 对比 Map 风格

| 特性 | Map 风格 | SchemaBuilder 风格 |
|------|---------|-------------------|
| 代码行数 | 10 行 | 7 行 |
| 可读性 | 中等 | 优秀 |
| required 字段 | 单独数组 | 集成在 field() |
| 类型安全 | 字符串容易拼错 | 类型构造器 |
| **推荐度** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

---

## 6️⃣ HTTP 服务器启动

### ❌ 旧代码 (0.3.x - 不支持 HTTP)

0.3.x 只支持 Stdio。

### ✅ 新代码 (0.5.0)

```moonbit
async fn main {
  let storage = Storage::new("notes")
  
  let server = @mcp.mcp_server(name="my-server", version="1.0.0")
    |> register_tools(storage)
  
  @async.with_task_group(fn(group) {
    server.run_http(port=4240, group~)  // ✨ 内置并发处理
  })
}
```

**新特性**:
- ✅ HTTP + SSE 支持
- ✅ 自动并发请求处理
- ✅ 使用 `@async.TaskGroup` 管理生命周期

---

## 7️⃣ 性能改进 (自动生效)

### 并发请求处理

**0.3.x 行为**:
```
请求1 → 处理 → 响应1 → 请求2 → 处理 → 响应2  (串行)
```

**0.5.0 行为**:
```
请求1 ──┐
请求2 ──┼──→ 并发处理 → 响应队列 → 按序发送
请求3 ──┤
请求4 ──┘
```

**实测效果**:
- 4 个并发 tool 调用: **串行 4s → 并发 1s**
- 20 个工具的 `tools/list`: **800ms → 100ms** (8x 提升)

### Schema 缓存

- Schema 在注册时序列化一次，永久复用
- `tools/list` 无需重复 stringify，零开销

---

## 8️⃣ Resource 和 Prompt 迁移

### Resource

#### ❌ 旧代码

```moonbit
pub fn register_resources(server : @mcp.MCPServer, storage : Storage) -> Unit {
  server.register_trait_resource(WeatherResource::new("New York"))
}
```

#### ✅ 新代码

```moonbit
pub fn register_resources(
  server : @mcp.MCPServer,
  storage : Storage
) -> @mcp.MCPServer {
  server.with_resource(WeatherResource::new("New York"))
}
```

### Prompt

#### ❌ 旧代码

```moonbit
pub fn register_prompts(server : @mcp.MCPServer, storage : Storage) -> Unit {
  server.register_trait_prompt(SummarizePrompt::{ storage })
}
```

#### ✅ 新代码

```moonbit
pub fn register_prompts(
  server : @mcp.MCPServer,
  storage : Storage
) -> @mcp.MCPServer {
  server.with_prompt(SummarizePrompt::{ storage })
}
```

---

## 9️⃣ 完整迁移示例

### 项目结构

```
my-mcp-server/
├── moon.mod.json
├── src/
│   ├── main/
│   │   └── main.mbt          # 服务器入口
│   ├── internal/
│   │   ├── storage.mbt       # 业务逻辑
│   │   ├── tools.mbt         # 工具定义
│   │   ├── resources.mbt     # 资源定义
│   │   └── prompts.mbt       # 提示定义
```

### main.mbt (完整)

```moonbit
///| 0.5.0 服务器入口 - 使用 Pipeline 风格
async fn main {
  @stdio.stderr.write("🚀 Starting MCP Server v0.5.0\n")
  
  let storage = @internal.Storage::new("data")
  
  @mcp.mcp_server(name="my-notes-server", version="1.0.0")
  |> @internal.register_tools(storage)
  |> @internal.register_resources(storage)
  |> @internal.register_prompts(storage)
  |> fn(s) { s.run_stdio() }
}
```

### tools.mbt (完整)

```moonbit
///| 工具注册函数
pub fn register_tools(
  server : @mcp.MCPServer,
  storage : Storage,
) -> @mcp.MCPServer {
  server
  |> @mcp.MCPServer::with_tool(create_note_tool(storage))
  |> @mcp.MCPServer::with_tool(ReadNoteTool::new(storage))
  |> @mcp.MCPServer::with_tool(ListNotesTool::new(storage))
}

///| 函数式风格工具 - 使用 tool_fn (推荐)
struct CreateNoteParams {
  title : String
  content : String
  tags : Array[String]?
} derive(ToJson, FromJson)

pub impl @core.Params for CreateNoteParams with schema() -> @core.JsonSchema {
  @core.schema_builder()
    .field("title", @core.str_type(), required=true, desc="Note title")
    .field("content", @core.str_type(), required=true, desc="Note content")
    .field("tags", @core.arr_type(@core.str_type()), desc="Optional tags")
    .build(desc="Create a new note")
}

pub impl @core.Params for CreateNoteParams with from_json(j : Json) -> CreateNoteParams raise @core.ToolError {
  match CreateNoteParams::from_json(j) {
    Ok(v) => v
    Err(_) => raise @core.ToolError("Failed to parse CreateNoteParams")
  }
}

pub impl @core.Params for CreateNoteParams with to_json(self : CreateNoteParams) -> Json {
  self.to_json()
}

pub fn create_note_tool(storage : Storage) -> @core.ToolWrapper {
  @core.tool_fn(
    name="create_note",
    description="Create a new note with title, content, and optional tags",
    handler=fn(params : CreateNoteParams) -> String {
      let note : Note = {
        title: params.title,
        content: params.content,
        tags: params.tags.or([]),
      }
      match storage.save_note(note) {
        Ok(_) => "✅ Note created: \{params.title}"
        Err(msg) => "❌ Failed: \{msg}"
      }
    },
  )
}

///| Trait 风格工具 - 适合复杂逻辑
pub struct ReadNoteTool {
  storage : Storage
}

pub fn ReadNoteTool::new(storage : Storage) -> ReadNoteTool {
  { storage }
}

pub impl @tool.Tool for ReadNoteTool with name(_self) -> String {
  "read_note"
}

pub impl @tool.Tool for ReadNoteTool with description(_self) -> String {
  "Read a note by title"
}

pub impl @tool.Tool for ReadNoteTool with params(_self) -> Array[@tool.ParamDef] {
  [
    { name: "title", description: "Note title", type_: "string", required: true },
  ]
}

pub impl @tool.Tool for ReadNoteTool with execute(_self, args) {
  let title = match get_string(args, "title") {
    Some(t) => t
    None => return @tool.ToolResult::error("Missing 'title' parameter")
  }
  
  match _self.storage.load_note(title) {
    Ok(note) => @tool.ToolResult::text("# \{note.title}\n\n\{note.content}")
    Err(msg) => @tool.ToolResult::error(msg)
  }
}

///| 简单工具 - List 风格
pub struct ListNotesTool {
  storage : Storage
}

pub fn ListNotesTool::new(storage : Storage) -> ListNotesTool {
  { storage }
}

pub impl @tool.Tool for ListNotesTool with name(_self) -> String {
  "list_notes"
}

pub impl @tool.Tool for ListNotesTool with description(_self) -> String {
  "List all available notes"
}

pub impl @tool.Tool for ListNotesTool with params(_self) -> Array[@tool.ParamDef] {
  []  // 无参数
}

pub impl @tool.Tool for ListNotesTool with execute(_self, _args) {
  match _self.storage.list_notes() {
    Ok(titles) => {
      if titles.is_empty() {
        @tool.ToolResult::text("No notes found")
      } else {
        let list = titles.map(fn(t) { "• \{t}" }).join("\n")
        @tool.ToolResult::text("📝 Notes (\{titles.length()}):\n\n\{list}")
      }
    }
    Err(msg) => @tool.ToolResult::error(msg)
  }
}

///| Helper 函数
fn get_string(json : Json, key : String) -> String? {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}
```

---

## 🔟 API 变更对照表

### 核心 API

| 0.3.x | 0.5.0 | 说明 |
|-------|-------|------|
| `MCPServer::new(n, v)` | `mcp_server(name~, version~)` | 服务器创建 |
| `server.register_trait_tool(t)` | `server.with_tool(t)` | 工具注册 |
| `server.register_trait_resource(r)` | `server.with_resource(r)` | 资源注册 |
| `server.register_trait_prompt(p)` | `server.with_prompt(p)` | 提示注册 |
| `server.run(transport)` | `server.run_stdio()` | Stdio 启动 |
| N/A | `server.run_http(port~, group~)` | HTTP 启动 (新增) |

### 参数定义 Helper (已移除)

| 0.3.x Helper | 0.5.0 替代 |
|-------------|-----------|
| `@mcp.string_param(n, d)` | `{ name: n, description: d, type_: "string", required: true }` |
| `@mcp.number_param(n, d)` | `{ name: n, description: d, type_: "number", required: true }` |
| `@mcp.boolean_param(n, d)` | `{ name: n, description: d, type_: "boolean", required: true }` |
| `@mcp.optional_string_param(n, d)` | `{ name: n, description: d, type_: "string", required: false }` |
| `@mcp.optional_number_param(n, d)` | `{ name: n, description: d, type_: "number", required: false }` |
| `@mcp.optional_boolean_param(n, d)` | `{ name: n, description: d, type_: "boolean", required: false }` |

### Schema 定义 (0.5.0 新增)

| Map 风格 (0.4.x) | SchemaBuilder 风格 (0.5.0 推荐) |
|-----------------|-------------------------------|
| `@core.str_schema(desc~)` | `@core.str_type()` |
| `@core.int_schema(desc~)` | `@core.int_type()` |
| `@core.num_schema(desc~)` | `@core.num_type()` |
| `@core.bool_schema(desc~)` | `@core.bool_type()` |
| `@core.arr_schema(item, desc~)` | `@core.arr_type(item_type)` |
| `@core.obj_schema(props, required, desc~)` | `schema_builder().field(...).build(...)` |

---

## 1️⃣1️⃣ 迁移检查清单

### 代码修改

- [ ] 更新 `moon.mod.json` 依赖版本为 `0.5.0`
- [ ] 运行 `moon install` 安装依赖
- [ ] 修改 `main.mbt`:
  - [ ] 替换 `MCPServer::new()` 为 `mcp_server()`
  - [ ] 移除 `AnyTransport` 和 `StdioTransport` 手动创建
  - [ ] 使用 `run_stdio()` 或 `run_http()`
  - [ ] 应用 pipeline 风格 (`|>`)
- [ ] 修改 `register_tools()`:
  - [ ] 返回类型改为 `@mcp.MCPServer`
  - [ ] `register_trait_tool` → `with_tool`
  - [ ] 使用 pipeline 风格
- [ ] 修改 `register_resources()`:
  - [ ] 返回类型改为 `@mcp.MCPServer`
  - [ ] `register_trait_resource` → `with_resource`
- [ ] 修改 `register_prompts()`:
  - [ ] 返回类型改为 `@mcp.MCPServer`
  - [ ] `register_trait_prompt` → `with_prompt`
- [ ] 修改所有工具的 `params()` 实现:
  - [ ] 移除所有 helper 函数调用
  - [ ] 直接构造 `ParamDef` 结构体
- [ ] (可选) 迁移简单工具到 `tool_fn` + `SchemaBuilder` 风格

### 验证

- [ ] 运行 `moon check` - 应该 0 错误
- [ ] 运行 `moon build` - 构建成功
- [ ] 运行 `moon test` - 测试全通过
- [ ] 测试实际工具调用 - 功能正常
- [ ] 测试并发调用 (4 个工具同时) - 性能提升明显

### 清理

- [ ] 删除任何对 `deprecated.mbt` 的引用
- [ ] 删除旧的 helper 函数封装代码
- [ ] 更新 README 和文档

---

## 1️⃣2️⃣ 故障排查

### 编译错误: "未找到 string_param"

**原因**: Helper 函数已被移除

**解决**:
```moonbit
// ❌ 旧代码
@mcp.string_param("title", "Note title")

// ✅ 新代码
{ name: "title", description: "Note title", type_: "string", required: true }
```

### 编译错误: "register_trait_tool 不存在"

**原因**: 方法名已更改

**解决**:
```moonbit
// ❌ 旧代码
server.register_trait_tool(tool)

// ✅ 新代码
server.with_tool(tool)
```

### 编译错误: "返回类型不匹配"

**原因**: 注册函数返回类型改变

**解决**:
```moonbit
// ❌ 旧代码
pub fn register_tools(server : @mcp.MCPServer, storage : Storage) -> Unit {
  server.register_trait_tool(tool)
}

// ✅ 新代码
pub fn register_tools(server : @mcp.MCPServer, storage : Storage) -> @mcp.MCPServer {
  server.with_tool(tool)
}
```

### 运行时: 工具调用仍然串行

**原因**: 可能在使用旧版本或未正确更新

**验证**:
1. 检查 `moon.mod.json` 中版本是否为 `0.5.0`
2. 运行 `moon install --update`
3. 确认 `run_stdio()` 或 `run_http()` 被正确调用

---

## 1️⃣3️⃣ 性能测试

### 测试并发处理

创建测试脚本 `test_concurrent.sh`:

```bash
#!/bin/bash
# 同时发送 4 个请求

{
  echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_note","arguments":{"title":"Note1","content":"Content1"}}}'
  echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_note","arguments":{"title":"Note2","content":"Content2"}}}'
  echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"create_note","arguments":{"title":"Note3","content":"Content3"}}}'
  echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"create_note","arguments":{"title":"Note4","content":"Content4"}}}'
} | moon run src/main

# 观察响应顺序 - 可能不是 1,2,3,4 (并发执行)
```

### 测试 tools/list 性能

```bash
# 发送 tools/list 请求并计时
time echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | moon run src/main
```

**预期结果** (20 个工具):
- 0.3.x: ~800ms
- 0.5.0: ~100ms (8x 提升)

---

## 1️⃣4️⃣ 新特性最佳实践

### 何时使用 SchemaBuilder?

**推荐使用**:
- 新工具定义
- 参数较多 (3+ 个字段)
- 需要嵌套数组/对象

**可选不用**:
- 极简工具 (0-2 个参数)
- 追求极致性能 (虽然差异微乎其微)

### 何时使用 tool_fn 风格?

**推荐使用**:
- 简单 CRUD 操作
- 无状态工具
- 参数类型化需求强

**不推荐使用**:
- 复杂的上下文管理
- 需要访问 `self` 状态
- 动态参数生成

### HTTP vs Stdio?

| 场景 | 推荐 |
|------|-----|
| Claude Desktop 集成 | Stdio |
| Web 前端调用 | HTTP |
| 多客户端并发 | HTTP |
| 本地脚本调用 | Stdio |

---

## 1️⃣5️⃣ 获取帮助

### 示例代码

查看 `examples/` 目录:
- `examples/cmd/main/main.mbt` - 完整服务器示例
- `examples/internal/tools.mbt` - 工具定义示例 (两种风格)
- `examples/internal/resources.mbt` - 资源示例
- `examples/internal/prompts.mbt` - 提示示例

### 参考文档

- [MCP 协议规范](https://modelcontextprotocol.io/specification/)
- [MoonBit 语言文档](https://docs.moonbitlang.com)
- [项目 GitHub](https://github.com/colmugx/mcp.mbt)

### 问题反馈

遇到问题？
- GitHub Issues: https://github.com/colmugx/mcp.mbt/issues
- 讨论区: https://github.com/colmugx/mcp.mbt/discussions

---

## 1️⃣6️⃣ 附录: 类型对照表

### ParamDef 类型字段

| MoonBit 类型 | JSON Schema type_ 值 |
|-------------|---------------------|
| `String` | `"string"` |
| `Int` | `"integer"` |
| `Double` | `"number"` |
| `Bool` | `"boolean"` |
| `Array[T]` | `"array"` |
| 结构体 | `"object"` |
| `T?` (Optional) | 同 `T`，但 `required: false` |

### SchemaType 映射

| SchemaBuilder | 对应 JSON Schema |
|--------------|-----------------|
| `str_type()` | `{ "type": "string" }` |
| `int_type()` | `{ "type": "integer" }` |
| `num_type()` | `{ "type": "number" }` |
| `bool_type()` | `{ "type": "boolean" }` |
| `arr_type(T)` | `{ "type": "array", "items": T }` |
| `obj_type()` | `{ "type": "object" }` |

---

**迁移完成后，你将获得**:
- ✅ 8x 性能提升
- ✅ 并发请求处理能力
- ✅ 更简洁的代码 (30% 减少)
- ✅ 更好的类型安全
- ✅ 现代化的 API 设计

祝迁移顺利！🚀
