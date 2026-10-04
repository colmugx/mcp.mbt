///|
/// One reader owns the transport while every caller waits on its own id-routed queue.
async fn[T] MCPClient::pump_direct_responses(
  self : MCPClient,
  group : @async.TaskGroup[T],
) -> Unit {
  self.receive_mutex.acquire()
  defer self.receive_mutex.release()
  while !self.response_map.is_empty() && !self.event_loop_started {
    let message = self.transport.receive() catch {
      error => {
        if @async.is_being_cancelled() {
          raise error
        }
        self.close_pending_response_queues()
        return
      }
    }
    match message {
      Some(message) => self.route_received_message(message, group)
      None => {
        self.close_pending_response_queues()
        return
      }
    }
  }
}

///|
fn MCPClient::close_pending_response_queues(self : MCPClient) -> Unit {
  let queues = self.response_map.values().collect()
  self.response_map.clear()
  for queue in queues {
    queue.close(clear=true)
  }
}

///|
fn[T] MCPClient::route_received_message(
  self : MCPClient,
  message : String,
  group : @async.TaskGroup[T],
) -> Unit {
  let json = @json.parse(message) catch {
    _ => {
      self.close_pending_response_queues()
      return
    }
  }
  guard json is Object(obj) else {
    self.close_pending_response_queues()
    return
  }
  if obj.get("method") is Some(_) && obj.get("id") is Some(_) {
    if self.legacy_mode {
      self.handle_server_request(obj, group)
    } else {
      let id = obj.get("id").unwrap_or(Json::null())
      let response = jsonrpc_error_str(
        id, -32601, "method not found: server-initiated requests were removed in MCP 2026-07-28, use MRTR inputRequests",
      )
      group.spawn_bg(() => self.transport.send(response) catch { _ => () })
    }
  } else if obj.get("method") is Some(String(method_name)) {
    let notification : @types.Notification = {
      method_name,
      params: obj.get("params"),
    }
    match extract_subscription_id(notification.params) {
      Some(sub_id) =>
        match self.subscription_handlers.get(sub_id) {
          Some(handler) => handler(notification.params.unwrap_or(Json::null()))
          None =>
            handle_server_notification(self.notification_handlers, notification)
        }
      None =>
        handle_server_notification(self.notification_handlers, notification)
    }
  } else if obj.get("id") is Some(_) {
    self.dispatch_response(message, obj)
  }
}
