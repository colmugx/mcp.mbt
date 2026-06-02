# 2. 协议类型参考

所有协议类型定义在 `colmugx/mcp/protocol/types` 包中。

```moonbit
// moon.pkg
import { "colmugx/mcp/protocol/types" }
```

## 2.1 JSON-RPC 消息

### RequestId

```moonbit
pub(all) enum RequestId {
  Int(Int)     // 数字 ID
  Str(String)  // 字符串 ID
} derive(Eq, Show)
```

`RequestId` 支持 JSON-RPC 2.0 规范中的数字和字符串两种 ID 格式。

### JsonRpcRequest

```moonbit
pub(all) struct JsonRpcRequest {
  jsonrpc : String      // 始终为 "2.0"
  id : RequestId        // 请求 ID（Int 或 String）
  method_name : String  // 方法名，如 "tools/list"
  params : Json         // 参数对象
} derive(Eq, Show)
```

从 JSON 解析：

```moonbit
let json = @json.parse(raw_string)
match JsonRpcRequest::from_json(json) {
  Ok(req) => // 使用 req.method_name, req.params 等
  Err(e) => // 处理解析错误
}
```

### JsonRpcResponse

```moonbit
pub(all) struct JsonRpcResponse {
  jsonrpc : String
  id : RequestId
  result : Result[Json, JsonRpcError]
} derive(Eq, Show)
```

### JsonRpcError

```moonbit
pub(all) struct JsonRpcError {
  code : Int       // 错误码
  message : String // 错误信息
  data : Json?     // 附加数据
} derive(Eq, Show)
```

标准错误码：

| 错误码 | 含义 |
|--------|------|
| -32700 | ParseError — JSON 解析失败 |
| -32600 | InvalidRequest — 请求格式无效 |
| -32601 | MethodNotFound — 方法不存在 |
| -32602 | InvalidParams — 参数无效 |
| -32603 | InternalError — 服务器内部错误 |
| -32000 | ToolError — 工具执行错误 |

## 2.2 MCP 错误类型

### MCPError（协议层错误）

```moonbit
pub(all) suberror MCPError {
  ParseError(String)         // -32700
  InvalidRequest(String)     // -32600
  MethodNotFound(String)     // -32601
  InvalidParams(String)      // -32602
  InternalError(String)      // -32603
  TransportError(TransportError)
  ToolError(String)          // -32000
} derive(Eq, Show)
```

方法：

- `MCPError::message(self) -> String` — 获取错误消息
- `MCPError::to_error_code(self) -> Int` — 获取 JSON-RPC 错误码

### TransportError（传输层错误）

```moonbit
pub(all) suberror TransportError {
  ConnectionClosed       // 连接已关闭
  ReadError(String)      // 读取失败
  WriteError(String)     // 写入失败
  Timeout                // 操作超时
  InvalidState(String)   // 状态无效（如在关闭后发送）
} derive(Eq, Show)
```

### ToolError（参数解析错误）

```moonbit
pub suberror ToolError {
  ToolError(String)
}
```

用于 `Params::from_json` 中的参数验证错误。

## 2.3 ContentItem（内容项）

```moonbit
pub(all) enum ContentItem {
  Text(String)                            // 文本内容
  Image(String, mime_type~ : String)      // Base64 图片
  ResourceLink(String)                    // 资源 URI 引用（type: "resource_link"）
  EmbeddedResource(EmbeddedResourceContent) // 内嵌资源内容（type: "resource"）
} derive(Eq, Show)
```

`ContentItem` 是 Tool、Resource、Prompt 之间共享的内容类型，定义在 `protocol/types` 中。

### EmbeddedResourceContent

```moonbit
pub(all) enum EmbeddedResourceContent {
  Text(String, uri~ : String, mime_type~ : String?)   // 内嵌文本资源
  Blob(String, uri~ : String, mime_type~ : String)    // 内嵌二进制资源
} derive(Eq, Show)
```

`EmbeddedResourceContent` 表示内嵌在消息中的资源内容，包含 URI 和可选的 MIME 类型。

## 2.4 通知类型

### Notification

```moonbit
pub(all) struct Notification {
  method_name : String  // 如 "notifications/tools/list_changed"
  params : Json?        // 可选参数
} derive(Eq, Show)
```

### 工厂方法

```moonbit
tools_list_changed_notification()                -> Notification
resources_list_changed_notification()            -> Notification
prompts_list_changed_notification()              -> Notification
resources_updated_notification(uri : String)     -> Notification
progress_notification(token : String, progress : Double, total? : Double) -> Notification
cancelled_notification(request_id : String, reason? : String) -> Notification
```

### NotificationCapabilities

```moonbit
pub(all) struct NotificationCapabilities {
  tools_list_changed : Bool
  resources_list_changed : Bool
  resources_updated : Bool
  prompts_list_changed : Bool
} derive(Eq, Show)
```

## 2.5 Server 类型

### ServerInfo

```moonbit
pub(all) struct ServerInfo {
  name : String
  title : String?        // 可选标题
  version : String
  description : String?  // 可选描述
} derive(Eq, Show)
```

### ServerCapabilities

```moonbit
pub(all) struct ServerCapabilities {
  tools : ToolCapabilities?       // 工具能力
  resources : ResourceCapabilities? // 资源能力
  prompts : PromptCapabilities?   // 提示能力
} derive(Eq, Show)
```

### ToolDefinition

```moonbit
pub(all) struct ToolDefinition {
  name : String
  description : String
  input_schema : Json
  cached_schema_json : String
  icon : String?  // 可选图标
} derive(Eq, Show)
```

## 2.6 Client 类型

### ClientInfo

```moonbit
pub(all) struct ClientInfo {
  name : String
  title : String?     // 可选标题
  version : String
} derive(Eq, Show)
```

### ClientCapabilities

```moonbit
pub(all) struct ClientCapabilities {
  roots : RootCapabilities?         // 文件系统根目录能力
  sampling : SamplingCapabilities?  // 支持 sampling（空结构体标记）
  elicitation : ElicitationCapabilities?  // 支持 elicitation
} derive(Eq, Show)
```

默认值通过 `default_capabilities()` 设置，启用全部三种能力。

### RootCapabilities

```moonbit
pub(all) struct RootCapabilities {
  list_changed : Bool
} derive(Eq, Show)
```

### SamplingCapabilities

```moonbit
pub(all) struct SamplingCapabilities {
  // 空结构体，标记客户端支持 sampling/createMessage
} derive(Eq, Show)
```

### ElicitationCapabilities

```moonbit
pub(all) struct ElicitationCapabilities {
  form : Bool  // 是否支持表单输入
} derive(Eq, Show)
```

## 2.7 Client 扩展类型（双向通信）

以下类型用于 server→client 请求（sampling、roots、elicitation）和通知：

### Root

```moonbit
pub(all) struct Root {
  uri : String    // 根目录 URI
  name : String?  // 可选名称
} derive(Eq, Show)
```

### SamplingMessage

```moonbit
pub(all) struct SamplingMessage {
  role : String       // "user" 或 "assistant"
  content : ContentItem
} derive(Eq, Show)
```

### CreateMessageRequest

```moonbit
pub(all) struct CreateMessageRequest {
  messages : Array[SamplingMessage]
  max_tokens : Int
  system_prompt : String?
  include_context : String?
  temperature : Double?
  stop_sequences : Array[String]?
  metadata : Json?
} derive(Eq, Show)
```

### CreateMessageResult

```moonbit
pub(all) struct CreateMessageResult {
  role : String
  model : String
  content : ContentItem
  stop_reason : String?
} derive(Eq, Show)
```

### ElicitationRequest

```moonbit
pub(all) struct ElicitationRequest {
  message : String
  requested_schema : Json
} derive(Eq, Show)
```

### ElicitationResult

```moonbit
pub(all) struct ElicitationResult {
  action : String    // "accept", "decline", "cancel"
  content : Json?    // 用户输入内容
} derive(Eq, Show)
```

### ProgressNotification

```moonbit
pub(all) struct ProgressNotification {
  progress_token : String
  progress : Double
  total : Double?
  message : String?
} derive(Eq, Show)
```

### CancelledNotification

```moonbit
pub(all) struct CancelledNotification {
  request_id : RequestId  // Int 或 Str
  reason : String?
} derive(Eq, Show)
```

### ResourceUpdatedNotification

```moonbit
pub(all) struct ResourceUpdatedNotification {
  uri : String  // 变更的资源 URI
} derive(Eq, Show)
```

## 2.8 Prompt 类型

```moonbit
pub(all) struct PromptArgument {
  name : String
  description : String?
  required : Bool?
} derive(Eq, Show)

pub(all) struct Prompt {
  name : String
  description : String?
  arguments : Array[PromptArgument]?
} derive(Eq, Show)

pub(all) struct PromptMessage {
  role : String        // "user" 或 "assistant"
  content : ContentItem
} derive(Eq, Show)

pub(all) struct GetPromptResult {
  description : String?
  messages : Array[PromptMessage]
} derive(Eq, Show)
```
