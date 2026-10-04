///|
fn scoped_request_key(scope : String, id : String) -> String {
  if scope == "" {
    id
  } else {
    scope + ":" + id
  }
}

///|
fn MCPServer::new_request_scope(self : MCPServer) -> String {
  let id = self.next_scope_id
  self.next_scope_id += 1
  "transport:" + id.to_string()
}

///|
fn MCPServer::cancel_scope(self : MCPServer, scope : String) -> Unit {
  let prefix = scope + ":"
  let requests = self.active_requests.to_array()
  for (key, token) in requests {
    if key.has_prefix(prefix) {
      token.cancel()
    }
  }
  let subscriptions = self.subscriptions.to_array()
  for (key, sub) in subscriptions {
    if key.has_prefix(prefix) {
      sub.cancellation_registration.dispose()
      self.subscriptions.remove(key)
      sub.cancellation_token.cancel()
    }
  }
}

///|
/// Transport cancellation is request-local; the same JSON-RPC id on another peer is unrelated.
async fn MCPServer::dispatch_runtime_request(
  self : MCPServer,
  request : @types.JsonRpcRequest,
  reply : @aqueue.Queue[String],
  group : @async.TaskGroup[Unit],
  scope : String,
  principal : @runtime.Principal?,
  token : @runtime.CancellationToken,
) -> Unit {
  if is_fast_method(request.method_name) {
    if token.is_cancelled() {
      return
    }
    let response = self.handle_parsed_request(
      request,
      principal?,
      cancellation_token=token,
    ) catch {
      error => {
        if token.is_cancelled() || @async.is_cancellation_error(error) {
          return
        }
        internal_error_response(request.id)
      }
    }
    if !token.is_cancelled() {
      reply.put(response) catch {
        _ => ()
      }
    }
    return
  }
  let key = scoped_request_key(scope, request.id.to_json_string())
  if self.active_requests.contains(key) || self.subscriptions.contains(key) {
    reply.put(
      jsonrpc_error_str(request.id, -32600, "Duplicate active request id"),
    )
    return
  }
  self.active_requests.set(key, token)
  let finished = Ref(false)
  let registration : Ref[@runtime.CancellationRegistration?] = Ref(None)
  let task = group.spawn(
    () => {
      defer {
        finished.val = true
        match registration.val {
          Some(registration) => registration.dispose()
          None => ()
        }
        self.active_requests.remove(key)
      }
      if token.is_cancelled() {
        return
      }
      let reporter = @runtime.ProgressReporter::new(
        (progress, total, message) => {
          token.throw_if_cancelled()
          let progress_token = match request.params {
            Object(params) =>
              match params.get("_meta") {
                Some(Object(meta)) => meta.get("progressToken")
                _ => None
              }
            _ => None
          }
          if progress_token is Some(progress_token) {
            let fields : Map[String, Json] = {
              "progressToken": progress_token,
              "progress": Json::number(progress),
            }
            if total is Some(total) {
              fields.set("total", Json::number(total))
            }
            if message is Some(message) {
              fields.set("message", Json::string(message))
            }
            reply.put(
              Json::object({
                "jsonrpc": "2.0",
                "method": "notifications/progress",
                "params": Json::object(fields),
              }).stringify(),
            )
          }
        },
        cancellation_token=token,
      )
      let response = self.handle_parsed_request(
        request,
        principal?,
        cancellation_token=token,
        progress_reporter=reporter,
      ) catch {
        error => {
          if token.is_cancelled() || @async.is_cancellation_error(error) {
            return
          }
          internal_error_response(request.id)
        }
      }
      if !token.is_cancelled() && !@async.is_being_cancelled() {
        reply.put(response) catch {
          _ => ()
        }
      }
    },
    no_wait=true,
  )
  if !finished.val {
    registration.val = Some(token.on_cancel(fn() { task.cancel() }))
  }
}
