///|
/// 2025-11-25 Streamable HTTP session-aware client transport.
///
/// This transport is intentionally separate from the modern `@transport.AnyTransport`
/// enum: it holds a `Mcp-Session-Id` returned during `initialize` and re-sends it on
/// every subsequent POST. It also terminates the session with an HTTP DELETE in
/// `close`. The legacy GET long-poll SSE channel and `Last-Event-ID` resumability
/// are not implemented.
pub struct LegacyHttpSessionTransport {
  base_url : String
  auth_token : String?
  mut session_id : String?
  mut closed : Bool
  pending_responses : @async.Queue[String]
  /// Caller-supplied headers appended to every outgoing request after the
  /// built-in set; same-name entries override the built-ins (last write wins,
  /// same contract as the modern `HttpClientTransport`).
  extra_headers : Array[(String, String)]
}

///|
pub fn LegacyHttpSessionTransport::LegacyHttpSessionTransport(
  url~ : String,
  auth_token? : String = "",
  extra_headers? : Array[(String, String)] = [],
) -> LegacyHttpSessionTransport {
  {
    base_url: url,
    auth_token: if auth_token == "" {
      None
    } else {
      Some(auth_token)
    },
    session_id: None,
    closed: false,
    pending_responses: @async.Queue(kind=Unbounded),
    extra_headers,
  }
}

///|
/// Fill in the common request headers for legacy Streamable HTTP.
fn LegacyHttpSessionTransport::apply_request_headers(
  self : LegacyHttpSessionTransport,
  headers : @http.Headers,
) -> Unit {
  headers["Content-Type"] = "application/json"
  headers["Accept"] = "application/json, text/event-stream"
  headers["MCP-Protocol-Version"] = legacy_protocol_version
  match self.auth_token {
    Some(t) => headers["Authorization"] = "Bearer " + t
    None => ()
  }
  match self.session_id {
    Some(s) => headers["Mcp-Session-Id"] = s
    None => ()
  }
  for entry in self.extra_headers {
    let (name, value) = entry
    headers[name] = value
  }
}

///|
/// Perform the HTTP POST, handle status codes, capture the session id, and return
/// the connected client positioned at the response body.

///|
/// Cancellation note: error-translating catches below re-raise when
/// `@async.is_being_cancelled()` so a `with_timeout` cancellation keeps its
/// identity instead of surfacing as WriteError/ReadError to callers.
async fn LegacyHttpSessionTransport::do_post(
  self : LegacyHttpSessionTransport,
  message : String,
) -> (@http.Response, @http.Client) {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }
  let body_bytes = @utf8.encode(message)
  let headers : @http.Headers = Map([])
  self.apply_request_headers(headers)
  let client = @http.post_stream(self.base_url, headers~) catch {
    e =>
      if @async.is_being_cancelled() {
        raise e
      } else {
        raise @types.WriteError("HTTP POST failed: \{e}")
      }
  }
  // On success the client escapes via the return value, so only failure
  // paths (including async cancellation) may release it here.
  errdefer client.close()
  client.write(body_bytes) catch {
    e =>
      if @async.is_being_cancelled() {
        raise e
      } else {
        raise @types.WriteError("Failed to write body: \{e}")
      }
  }
  client.flush() catch {
    e =>
      if @async.is_being_cancelled() {
        raise e
      } else {
        raise @types.WriteError("Failed to flush: \{e}")
      }
  }
  let response = client.end_request() catch {
    e =>
      if @async.is_being_cancelled() {
        raise e
      } else {
        raise @types.ReadError("Failed to get response: \{e}")
      }
  }
  if response.code == 401 {
    let www_auth = match response.headers.get("www-authenticate") {
      Some(v) => v
      None => ""
    }
    let msg = match www_auth {
      "" => "HTTP 401 Unauthorized"
      _ => "HTTP 401 Unauthorized — WWW-Authenticate: " + www_auth
    }
    raise @types.Unauthorized(msg)
  }
  if response.code == 403 {
    raise @types.Forbidden("HTTP 403 Forbidden — insufficient permissions")
  }
  if response.code >= 400 {
    // Read the response body so gate/protocol rejections keep their reason
    // (same shape as the modern `HttpClientTransport` 4xx error). The outer
    // errdefer releases the client on this raise.
    let body_str = try {
      let body = client.read_all()
      body.text()
    } catch {
      _ => ""
    }
    raise @types.HttpError(response.code, body_str)
  }
  // @http.Headers lookups are case-insensitive, so servers that spell the
  // header `mcp-session-id` or `MCP-SESSION-ID` are still recognized.
  match response.headers.get("Mcp-Session-Id") {
    Some(s) => self.session_id = Some(s)
    None => ()
  }
  (response, client)
}

///|
/// POST a JSON-RPC request to the legacy MCP endpoint. If the server returns an
/// `Mcp-Session-Id` header, it is stored for all later requests. Responses may be
/// a single JSON object or an SSE stream; every JSON-RPC payload is queued for
/// `receive`. SSE tokenization is shared with the modern transport via
/// `@transport.SseEventReader`.
pub async fn LegacyHttpSessionTransport::send(
  self : LegacyHttpSessionTransport,
  message : String,
) -> Unit {
  let (response, client) = self.do_post(message)
  // `send` fully consumes the client on every path, so plain `defer` is right.
  defer client.close()
  let content_type = match response.headers.get("content-type") {
    Some(ct) => ct.to_lower()
    None => "application/json"
  }
  if content_type.contains("text/event-stream") {
    // One reader per response stream keeps lexbuf state between events, so a
    // keepalive and the JSON-RPC reply arriving in one chunk are both read.
    let reader = @transport.SseEventReader::new(client)
    while true {
      let (data_opt, id_opt) = reader.next()
      match @transport.sse_event_verdict(data_opt, id_opt) {
        @transport.SseEventVerdict::Message(event_json) =>
          self.pending_responses.put(event_json) catch {
            _ => ()
          }
        @transport.SseEventVerdict::Skip => ()
        @transport.SseEventVerdict::Eof => break
      }
    }
  } else {
    let body = client.read_all() catch {
      e =>
        if @async.is_being_cancelled() {
          raise e
        } else {
          raise @types.ReadError("Failed to read response body: \{e}")
        }
    }
    let body_str = body.text() catch {
      e =>
        if @async.is_being_cancelled() {
          raise e
        } else {
          raise @types.ReadError("Failed to decode response body: \{e}")
        }
    }
    self.pending_responses.put(body_str) catch {
      _ => ()
    }
  }
}

///|
/// Drain the next response message queued by `send`. Returns `None` when the
/// queue is empty.
pub fn LegacyHttpSessionTransport::receive(
  self : LegacyHttpSessionTransport,
) -> String? {
  if self.closed {
    return None
  }
  let next = self.pending_responses.try_get() catch { _ => None }
  match next {
    Some(s) => Some(s)
    None => None
  }
}

///|
/// Send a JSON-RPC notification (no id, fire-and-forget). Per the 2025-11-25
/// spec the server answers with HTTP 202 Accepted and no body.
pub async fn LegacyHttpSessionTransport::send_notification(
  self : LegacyHttpSessionTransport,
  notification : @types.Notification,
) -> Unit {
  let json_body = notification.to_jsonrpc_string()
  let (_, client) = self.do_post(json_body)
  client.close()
}

///|
/// Best-effort session termination. If a session id is held, sends an HTTP DELETE
/// to the MCP endpoint with the `Mcp-Session-Id` header. Errors are ignored.
pub async fn LegacyHttpSessionTransport::close(
  self : LegacyHttpSessionTransport,
) -> Unit {
  if self.closed {
    return
  }
  match self.session_id {
    Some(sid) => {
      let headers : @http.Headers = Map([])
      headers["Mcp-Session-Id"] = sid
      match self.auth_token {
        Some(t) => headers["Authorization"] = "Bearer " + t
        None => ()
      }
      for entry in self.extra_headers {
        let (name, value) = entry
        headers[name] = value
      }
      try {
        let _ = @http.request(self.base_url, @http.Delete, headers, b"")
      } catch {
        _ => ()
      }
    }
    None => ()
  }
  self.closed = true
  self.pending_responses.close(clear=true)
}
