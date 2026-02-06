///|
/// StdioTransport with buffered I/O for improved performance.
/// Buffering reduces the number of syscalls and context switches,
/// which is critical for high-frequency request/response patterns.
pub struct StdioTransport {
  mut closed : Bool
  // @stdio.stdin is already buffered internally, so use it directly
  reader : @stdio.Input
  // Buffer writes with 8KB buffer to reduce syscalls
  // (stdout is not buffered by default, so we wrap it)
  writer : @io.BufferedWriter[@stdio.Output]
}

///|
pub fn StdioTransport::new() -> StdioTransport {
  {
    closed: false,
    // stdin is already buffered internally (has ReaderBuffer)
    reader: @stdio.stdin,
    // Wrap stdout with BufferedWriter to batch writes (8KB buffer)
    writer: @io.BufferedWriter::new(@stdio.stdout, size=8192),
  }
}

///|
pub async fn StdioTransport::receive(
  self : StdioTransport,
) -> String? raise @types.TransportError {
  if self.closed {
    return None
  }
  // Use the Reader trait's read_until method
  // (stdin is already buffered, so this is efficient)
  let line_opt = self.reader.read_until("\n") catch {
    e => raise @types.ReadError("Failed to read from stdin: " + e.to_string())
  }
  match line_opt {
    None => {
      self.closed = true
      None
    }
    Some(line_view) => {
      // Convert StringView to String, trim, and convert back to String
      let message = line_view.to_string().trim().to_string()
      if message.is_empty() {
        return self.receive()
      }
      Some(message)
    }
  }
}

///|
pub async fn StdioTransport::send(
  self : StdioTransport,
  message : String,
) -> Unit raise @types.TransportError {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }
  match validate_jsonrpc_message(message) {
    Err(e) =>
      raise @types.WriteError("Invalid JSON-RPC message: " + e.message())
    Ok(_) => ()
  }
  // Write to buffered writer (batches small writes)
  self.writer.write(message) catch {
    e => raise @types.WriteError("Failed to write to stdout: " + e.to_string())
  }
  self.writer.write("\n") catch {
    e => raise @types.WriteError("Failed to write newline: " + e.to_string())
  }
  // Flush immediately to ensure message is sent
  // (important for request-response pattern)
  self.writer.flush() catch {
    e => raise @types.WriteError("Failed to flush stdout: " + e.to_string())
  }
}

///|
pub fn StdioTransport::send_event(
  _self : StdioTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  ignore(event_type)
  ignore(data)
  ()
}

///|
pub fn StdioTransport::supports_streaming(_self : StdioTransport) -> Bool {
  false
}

///|
pub async fn StdioTransport::send_notification(
  self : StdioTransport,
  notification : @types.Notification,
) -> Unit raise @types.TransportError {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }
  let json = @internal.jsonrpc_notification(
    notification.method_name,
    notification.params,
  )
  // Write to buffered writer
  self.writer.write(json) catch {
    e =>
      raise @types.WriteError("Failed to send notification: " + e.to_string())
  }
  self.writer.write("\n") catch {
    e =>
      raise @types.WriteError("Failed to write newline: " + e.to_string())
  }
  self.writer.flush() catch {
    e =>
      raise @types.WriteError("Failed to flush notification: " + e.to_string())
  }
}

///|
pub fn StdioTransport::close(self : StdioTransport) -> Unit {
  if not(self.closed) {
    self.closed = true
  }
}
