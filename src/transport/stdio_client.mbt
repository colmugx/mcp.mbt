///|
/// StdioClientTransport — MCP host/client connecting to a local MCP server
/// via spawned child process.
///
/// Follows the MCP specification: the host spawns the server as a subprocess,
/// communicates via newline-delimited JSON-RPC over stdin/stdout pipes.
/// Stderr passes through to the parent for server-side logging.
///
/// Two-phase initialization:
///   1. `new()` stores configuration (command, arguments, env)
///   2. `start(group)` creates pipes and spawns the child process
///
/// Graceful shutdown (per MCP spec):
///   1. Close stdin pipe → signals EOF to child
///   2. Child detects EOF and exits
///   3. TaskGroup cancel_handler (SIGTERM → 5s → SIGKILL) handles stubborn processes
pub struct StdioClientTransport {
  cmd : String
  args : Array[String]
  extra_env : Map[String, String]
  mut closed : Bool
  mut reader : @process.ReadFromProcess?
  mut raw_writer : @process.WriteToProcess?
  mut writer : @io.BufferedWriter[@process.WriteToProcess]?
}

///|
pub fn StdioClientTransport::StdioClientTransport(
  cmd~ : String,
  args? : Array[String] = [],
  extra_env? : Map[String, String] = {},
) -> StdioClientTransport {
  {
    cmd,
    args,
    extra_env,
    closed: false,
    reader: None,
    raw_writer: None,
    writer: None,
  }
}

///|
/// Spawn the child process inside the given TaskGroup.
/// Creates stdin/stdout pipes, spawns the process, and wraps the writer
/// in a BufferedWriter (8KB) for efficient I/O.
///
/// Must be called before `send()` / `receive()`.
pub async fn StdioClientTransport::start(
  self : StdioClientTransport,
  group : @async.TaskGroup[Unit],
) -> Unit raise @types.TransportError {
  if self.closed {
    raise @types.InvalidState("Cannot start a closed transport")
  }
  if self.reader is Some(_) {
    raise @types.InvalidState("Transport already started")
  }
  // Create pipes for child stdin (host writes → child reads)
  let (stdin_input, stdin_writer) = @process.write_to_process() catch {
    e => raise @types.WriteError("Failed to create stdin pipe: \{e}")
  }
  // Create pipes for child stdout (child writes → host reads)
  let (stdout_reader, stdout_output) = @process.read_from_process() catch {
    e => raise @types.ReadError("Failed to create stdout pipe: \{e}")
  }
  // Spawn the child process with graceful cancel (SIGTERM → 5s → SIGKILL)
  let _process = @process.spawn(
    group,
    self.cmd,
    self.args,
    extra_env=self.extra_env,
    stdin=stdin_input,
    stdout=stdout_output,
    cancel_handler=@process.graceful_cancel(timeout=5000),
    no_wait=true,
  ) catch {
    e => raise @types.WriteError("Failed to spawn process '\{self.cmd}': \{e}")
  }
  self.reader = Some(stdout_reader)
  self.raw_writer = Some(stdin_writer)
  self.writer = Some(@io.BufferedWriter::new(stdin_writer, size=8192))
}

///|
/// Read one JSON-RPC message from the child's stdout.
/// Returns None on EOF (child closed stdout / process exited).
pub async fn StdioClientTransport::receive(
  self : StdioClientTransport,
) -> String? raise @types.TransportError {
  if self.closed {
    return None
  }
  let reader = match self.reader {
    Some(r) => r
    None =>
      raise @types.InvalidState("Transport not started — call start() first")
  }
  let line_opt = reader.read_until("\n") catch {
    e =>
      raise @types.ReadError(
        "Failed to read from child process: " + e.to_string(),
      )
  }
  match line_opt {
    None => {
      self.closed = true
      None
    }
    Some(line_view) => {
      let message = line_view.trim().to_owned()
      if message.is_empty() {
        return self.receive()
      }
      Some(message)
    }
  }
}

///|
/// Send a JSON-RPC message to the child's stdin.
/// Validates the message, writes it with a newline, and flushes immediately.
pub async fn StdioClientTransport::send(
  self : StdioClientTransport,
  message : String,
) -> Unit raise @types.TransportError {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }
  let writer = match self.writer {
    Some(w) => w
    None =>
      raise @types.InvalidState("Transport not started — call start() first")
  }
  match validate_jsonrpc_message(message) {
    Err(e) =>
      raise @types.WriteError("Invalid JSON-RPC message: " + e.message())
    Ok(_) => ()
  }
  writer.write(message) catch {
    e =>
      raise @types.WriteError(
        "Failed to write to child stdin: " + e.to_string(),
      )
  }
  writer.write("\n") catch {
    e => raise @types.WriteError("Failed to write newline: " + e.to_string())
  }
  writer.flush() catch {
    e =>
      raise @types.WriteError("Failed to flush child stdin: " + e.to_string())
  }
}

///|
/// Send a JSON-RPC notification (no id, fire-and-forget) to the child's stdin.
pub async fn StdioClientTransport::send_notification(
  self : StdioClientTransport,
  notification : @types.Notification,
) -> Unit raise @types.TransportError {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }
  let writer = match self.writer {
    Some(w) => w
    None =>
      raise @types.InvalidState("Transport not started — call start() first")
  }
  let json = notification.to_jsonrpc_string()
  writer.write(json) catch {
    e =>
      raise @types.WriteError("Failed to send notification: " + e.to_string())
  }
  writer.write("\n") catch {
    e => raise @types.WriteError("Failed to write newline: " + e.to_string())
  }
  writer.flush() catch {
    e =>
      raise @types.WriteError("Failed to flush notification: " + e.to_string())
  }
}

///|
/// Client transport does not push events to child process.
pub fn StdioClientTransport::send_event(
  _self : StdioClientTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  ignore(event_type)
  ignore(data)
  ()
}

///|
pub fn StdioClientTransport::supports_streaming(
  _self : StdioClientTransport,
) -> Bool {
  false
}

///|
/// Graceful shutdown per MCP spec:
/// 1. Close stdin writer → signals EOF to child process
/// 2. Close stdout reader → release pipe resources
/// 3. Mark transport as closed
/// The TaskGroup's cancel_handler handles forced termination if needed.
pub fn StdioClientTransport::close(self : StdioClientTransport) -> Unit {
  if self.closed {
    return
  }
  // Close writer first (signals EOF to child's stdin)
  match self.raw_writer {
    Some(w) => w.close()
    None => ()
  }
  self.writer = None
  self.raw_writer = None
  // Close reader
  match self.reader {
    Some(r) => r.close()
    None => ()
  }
  self.reader = None
  self.closed = true
}
