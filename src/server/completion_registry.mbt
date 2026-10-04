///|
/// Enabling an empty registry advertises completion support and returns no suggestions.
pub struct CompletionRegistry {
  handlers : Map[
    String,
    async (@runtime.RequestContext, @types.CompleteRequestParams) -> Result[
      @types.CompletionResult,
      @types.MCPError,
    ],
  ]
}

///|
pub fn CompletionRegistry::new() -> CompletionRegistry {
  { handlers: Map([]), }
}

///|
fn completion_reference_key(reference : @types.CompletionReference) -> String {
  match reference {
    Prompt(name~, ..) => "prompt:" + name
    Resource(uri~, ..) => "resource:" + uri
  }
}

///|
pub fn CompletionRegistry::register(
  self : CompletionRegistry,
  reference : @types.CompletionReference,
  handler : async (@runtime.RequestContext, @types.CompleteRequestParams) -> Result[
    @types.CompletionResult,
    @types.MCPError,
  ],
) -> CompletionRegistry {
  self.handlers.set(completion_reference_key(reference), handler)
  self
}

///|
async fn handle_completion(
  server : MCPServer,
  context : @runtime.RequestContext,
  params : Json,
) -> String {
  let id = context.request_id
  let registry = match server.completion_registry {
    Some(registry) => registry
    None =>
      return jsonrpc_error_str(
        id, -32601, "Completion capability is not enabled",
      )
  }
  let params = @types.CompleteRequestParams::from_json(params) catch {
    error => return jsonrpc_error_from(id, error)
  }
  let outcome = match
    registry.handlers.get(completion_reference_key(params.reference)) {
    Some(handler) => handler(context, params)
    None => Ok(@types.CompletionResult::new([]))
  }
  context.cancellation_token.throw_if_cancelled()
  match outcome {
    Ok(result) => {
      // Public records can be constructed directly; validate before publishing a wire result.
      ignore(@types.CompletionResult::from_json(result.to_json())) catch {
        _ =>
          return jsonrpc_error_str(
            id, -32603, "Handler returned an invalid completion result",
          )
      }
      jsonrpc_success_str(server, id, result.to_json())
    }
    Err(error) => jsonrpc_error_from(id, error)
  }
}

///|
pub fn MCPServer::with_completions(
  self : MCPServer,
  registry : CompletionRegistry,
) -> MCPServer {
  { ..self, completion_registry: Some(registry), }
}
