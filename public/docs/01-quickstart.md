# 1. 快速开始

MCP SDK for MoonBit 是一个类型安全的 Model Context Protocol 实现，支持 Server 和 Client 双模式，提供 STDIO 和 HTTP 双传输层。

## 1.1 安装

在 `moon.mod.json` 中添加依赖：

```json
{
  "deps": {
    "colmugx/mcp": "0.6.0"
  },
  "preferred-target": "native"
}
```

运行：

```bash
moon update
```

## 1.2 最简 Server（STDIO）

```moonbit
// 在 moon.pkg 中：
// import { "colmugx/mcp" }

async fn main {
  let server = mcp_server(
    name="my-server",
    version="1.0.0",
  )
  server.register_tool(
    "hello",
    "Say hello",
    Json::object({}),
    async fn(_args) { Ok(ToolResult::text("Hello from MCP!")) },
  )
  server.run_stdio()
}
```

通过 STDIO 传输运行 server，任何 MCP host（Claude Desktop、VS Code 等）都可以直接连接。

## 1.3 最简 Client

```moonbit
// 在 moon.pkg 中：
// import { "colmugx/mcp/client" }

async fn main {
  let client = MCPClient::new(
    name="my-client",
    version="1.0.0",
  )
  // 注：connect_stdio / connect_http 需要先设置 transport
  // 详见第 5 章 Client 开发指南
  client.close()
}
```

## 1.4 项目结构概览

```
src/
  protocol/       纯协议层 — 无 async 依赖，wasm-gc 兼容
    types/        JSON-RPC 类型、MCP 错误、通知、ContentItem
    core/         Params trait、JsonSchema、SchemaBuilder、tool_fn
    tool/         Tool trait、ToolResult、ParamDef
    prompt/       Prompt trait
    resource/     Resource trait
    internal/     内部 JSON 构建工具
  jsonutil/       公共 JSON builder 函数
  transport/      传输层 — native: stdio/http, wasm-gc: stub
  server/         Server 应用层
  client/         Client 应用层
```

**包引用关系：**

| 引用方式 | 包路径 | 说明 |
|---------|--------|------|
| `using @mcp` | `colmugx/mcp` | 顶层统一导出（推荐） |
| `using @server` | `colmugx/mcp/server` | Server 全部 API |
| `using @client` | `colmugx/mcp/client` | Client 全部 API |
| `using @transport` | `colmugx/mcp/transport` | Transport trait 和实现 |
| `using @ptypes` | `colmugx/mcp/protocol/types` | 协议类型（wasm-gc 可用） |
| `using @ptool` | `colmugx/mcp/protocol/tool` | Tool 类型（wasm-gc 可用） |
| `using @pcore` | `colmugx/mcp/protocol/core` | Params/Schema（wasm-gc 可用） |

## 1.5 目标平台

| 平台 | Protocol 层 | Transport 层 | Server/Client |
|------|------------|-------------|---------------|
| **native** | ✅ | ✅ | ✅ |
| **wasm-gc** | ✅ | stub（abort） | ❌ |
| **js** | ✅ | ❌ | ❌ |

Protocol 层可在 wasm-gc 上运行，用于纯消息构建、schema 验证等不需要 I/O 的场景。
