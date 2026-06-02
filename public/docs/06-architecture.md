# 6. 架构设计与跨平台

## 6.1 三层架构

```
┌─────────────────────────────────────────────────┐
│  Application Layer                               │
│  ┌──────────────┐  ┌──────────────┐              │
│  │  server/      │  │  client/      │             │
│  │  MCPServer    │  │  MCPClient   │             │
│  │  Registry     │  │  Builder     │             │
│  └──────┬───────┘  └──────┬───────┘             │
│         │                  │                      │
├─────────┼──────────────────┼──────────────────────┤
│  Transport Layer  (platform-specific)             │
│  ┌────────────────────────────────────────────┐  │
│  │  Transport trait + Stdio/Http/HttpClient   │  │
│  │  native: 完整实现  wasm-gc: stub           │  │
│  │  HttpClient: SSE + session management      │  │
│  └────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────┤
│  Protocol Layer  (platform-agnostic)              │
│  ┌─────────┐ ┌──────┐ ┌──────┐ ┌──────┐        │
│  │  types/  │ │ core/ │ │ tool/ │ │prompt/│       │
│  │  error   │ │params │ │ trait │ │trait  │       │
│  │  types   │ │schema │ │result │ │def    │       │
│  │  reqid   │ │builder│ │toTool │ │       │       │
│  └─────────┘ └──────┘ └──────┘ └──────┘        │
└──────────────────────────────────────────────────┘
```

### 依赖规则

| 层 | 可依赖 | 禁止依赖 |
|----|--------|----------|
| **Protocol** | `moonbitlang/core/json` | `moonbitlang/async/*` |
| **Transport** | Protocol + `moonbitlang/async/*` | Application |
| **Application** | Protocol + Transport + `moonbitlang/async/*` | — |

### 包依赖图

```
protocol/types ←── 无外部依赖（仅 moonbitlang/core/json）
protocol/tool  ←── protocol/types
protocol/prompt ←── protocol/types
protocol/resource ←── protocol/types
protocol/core  ←── protocol/tool
protocol/      ←── 所有 protocol/* 子包

transport/     ←── protocol/types, protocol/internal(jsonutil), moonbitlang/async/*
server/        ←── protocol/*, transport/, jsonutil
client/        ←── protocol/types, protocol/resource, protocol/prompt, transport/, jsonutil

(顶层)        ←── server, client, transport, protocol
```

## 6.2 跨平台策略

### Protocol 层（wasm-gc 兼容）

Protocol 层完全不含 async 依赖，所有类型和函数为纯数据操作：

```moonbit
// moon.pkg — 无 moonbitlang/async 依赖
import { "moonbitlang/core/json" }
```

可用场景：
- 在浏览器中构建 MCP 消息
- Schema 验证和生成
- JSON-RPC 编解码
- 类型安全的消息构造

### Transport 层（条件编译）

通过 `moon.pkg` 的 `targets` 字段按平台选择编译文件：

```
// src/transport/moon.pkg
options(
  targets: {
    "stdio.mbt": ["native"],
    "http_server.mbt": ["native"],
    "http_client.mbt": ["native"],
    "http_compliance_test.mbt": ["native"],
    "unimplemented.mbt": ["wasm-gc"],
  },
)
```

- `transport.mbt`（Transport trait 定义）在所有平台编译
- `stdio.mbt`、`http_server.mbt`、`http_client.mbt` 仅在 native 编译
- `unimplemented.mbt` 在 wasm-gc 编译，提供 abort stub

### 模块配置

```json
// moon.mod.json
{
  "preferred-target": "native"
}
```

Server/Client 只在 native 上运行（依赖 `moonbitlang/async`）。

## 6.3 错误处理模型

```
TransportError          MCPError
  (传输层)               (协议层)
  ConnectionClosed       ParseError
  ReadError              InvalidRequest
  WriteError             MethodNotFound
  Timeout                InvalidParams
  InvalidState           InternalError
                         TransportError ← 包装 TransportError
                         ToolError
```

错误传播规则：
- Transport 方法 `raise TransportError`
- Server/Client 方法 `raise MCPError`（或返回 `Result[_, MCPError]`）
- `MCPError::TransportError(te)` 用于在协议层包装传输错误
- Tool handler 直接返回 `ToolResult`（使用 `ToolResult::error()` 表示错误）
- Resource/Prompt handler 返回 `Result[_, MCPError]`

## 6.4 请求处理流程（Server）

```
Client Request (JSON string)
    │
    ▼
MCPServer::handle_request()
    │
    ├─ parse JSON ──── Err → ParseError
    │
    ├─ JsonRpcRequest::from_json()
    │                  └─ Err → InvalidRequest
    │
    └─ match method_name
        ├─ "initialize"         → handle_initialize()  [sync]
        ├─ "tools/list"         → handle_tools_list()  [sync]
        ├─ "tools/call"         → handle_tools_call()  [async]
        ├─ "resources/list"     → handle_resources_list() [sync]
        ├─ "resources/read"     → handle_resources_read() [async]
        ├─ "resources/subscribe"   → [sync]
        ├─ "resources/unsubscribe" → [sync]
        ├─ "prompts/list"       → handle_prompts_list() [sync]
        ├─ "prompts/get"        → handle_prompts_get()  [async]
        └─ _                    → MethodNotFound
```

### 快速路径 vs 慢速路径

Server 的 `run()` 循环区分两类请求：

- **快速路径**（`initialize`, `tools/list`, `resources/list`, `prompts/list`）：直接在主循环执行，不 spawn 协程
- **慢速路径**（`tools/call`, `resources/read`, `prompts/get`）：在 TaskGroup 中 spawn 新协程执行

判断依据：`is_fast_request()` 通过字符串包含检查方法名。

所有响应通过 `@aqueue.Queue` 统一排队，由专门的发送任务写入 transport。

## 6.5 协议版本

当前实现的协议版本：**2025-11-25**（代码基于 2025-06-18 规范）

| 版本 | 支持的方法 |
|------|-----------|
| 2025-11-25 | initialize, tools/*, resources/*, prompts/*, ping, logging/setLevel |
| 新增类型 | ClientInfo, ClientCapabilities, RootCapabilities, RequestId, EmbeddedResourceContent |
| 字段更新 | ServerInfo +title/description, ToolDefinition +icon |
| ContentItem 扩展 | ResourceLink, EmbeddedResource (Text/Blob) |

### 尚未实现的 2025-11-25 特性

| 特性 | 状态 | 说明 |
|------|------|------|
| Tasks | ❌ | 实验性异步任务（tasks/get, tasks/update, tasks/cancel） |
| Elicitation | ✅ Client | Client 端已实现（`on_elicitation` handler），Server 端未实现 |
| Sampling with Tools | ❌ | Server 端 agentic sampling |
| Server-side Completions | ❌ | Server 端 completion handler |
| Extensions | ❌ | 扩展协商框架 |
| OAuth/CIMD | ✅ Transport | Bearer token 验证 + Protected Resource Metadata（RFC 9728） |
| OAuth 2.1 Flow | ❌ | 授权码 + PKCE + Token Refresh（应用层逻辑） |

## 6.6 性能特性

- **BufferedWriter**：StdioTransport 使用 8KB 缓冲写入，减少系统调用
- **Schema 缓存**：ToolDefinition 预计算并缓存 `cached_schema_json`，避免重复序列化
- **注册顺序保留**：Tool/Resource/Prompt 按注册顺序返回列表
- **并发安全**：所有 async handler 通过 TaskGroup 管理生命周期

## 6.7 扩展开发

### 添加新的 MCP 方法

1. 在 `src/server/handler.mbt` 中添加 `handle_xxx` 函数
2. 在 `src/server/server.mbt` 的 `handle_request` match 中添加分支
3. 按需在 `src/protocol/types/` 中添加新类型
4. 如需 Client 支持，在 `src/client/request_builder.mbt` 添加构建函数
5. 在 `src/client/client.mbt` 中添加类型化的 `parse_xxx()` 函数和对应的 Client 方法
6. 如有新的结果类型，在 `src/client/client_types.mbt` 中定义

### 添加新的 Transport

1. 在 `src/transport/` 中创建新文件（如 `websocket.mbt`）
2. 实现 `Transport` trait
3. 在 `AnyTransport` enum 中添加新变体
4. 在 `moon.pkg` 的 `targets` 中标记平台支持
5. 在 `unimplemented.mbt` 中添加 wasm-gc stub
