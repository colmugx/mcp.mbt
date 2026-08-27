///|
/// StdioClientTransport — js implementation (node + bun, one code path).
///
/// MCP host/client connecting to a local MCP server via spawned child
/// process, communicating with newline-delimited JSON-RPC over stdin/stdout
/// pipes; stderr is inherited for server-side logging. Lifecycle mirrors the
/// native implementation in stdio_client.mbt (two-phase start, graceful
/// close = stdin EOF, forced kill after timeout).
///
/// Bridge architecture (see scripts probe conclusions): the moon js backend
/// cannot take `node:stream`/`node:child_process` members as values —
/// `#module` RHS forms are callee-only and dotted member paths generate
/// invalid ESM — so all Node interop lives in inline `extern "js"` snippets
/// that dynamically `import('node:...')` and return Promises; the Promises
/// are bridged into the coroutine world with `@js_async.Promise::wait`:
///   - read:  child.stdout → `Readable.toWeb` → `@js_async.ReadableStream::
///     from_js` (pipe intermediary with cancellation) → buffered
///     `read_until("\n")`, exactly like the native frame handling;
///   - write: child.stdin → `Writable.toWeb` → default writer; each
///     `send` is one awaited `write` (message + newline) so backpressure
///     and "written before send returns" are preserved;
///   - exit:  the exit listener is registered inside the spawn extern (the
///     child may exit the moment stdin EOF arrives), and every promise the
///     MoonBit side waits on is guaranteed to settle;
///   - close: stdin EOF + a JS-side kill timer, disarmed by the exit
///     promise — the sync `close()` cannot hang.

///|
/// Opaque JavaScript value (spawn options object, node stream handles).
#external
priv type JsAny

///|
/// Spawned child process (opaque node ChildProcess handle).
#external
priv type JsChildProcess

///|
/// Default writer of the web-converted child stdin stream (opaque).
#external
priv type JsStdinWriter

///|
/// Plain JS object `{ code : Int }` resolved by the exit listener
/// (`code = -1` when the child was killed by a signal — node passes null).
priv struct ChildExit {
  code : Int
}

///|
/// Result of a successful spawn: the child plus its pre-registered exit
/// promise. The extern shapes the plain JS object `{ child, exit }`.
priv struct StartedChild {
  child : JsChildProcess
  exit : @js_async.Promise[ChildExit]
}

///|
/// Spawn `cmd`, resolving with the child and its exit promise on the
/// node 'spawn' event, rejecting on spawn failure ('error' event).
/// Both listeners attach synchronously at spawn time because node emits
/// child 'error' on nextTick — before any promise continuation could.
/// A permanent no-op 'error' handler is installed on success so late
/// 'error' events (e.g. kill failures) cannot crash the process.
extern "js" fn js_start_child(
  cmd : String,
  args : Array[String],
  options : JsAny,
) -> @js_async.Promise[StartedChild] =
  #| async (cmd, args, options) => {
  #|   const { spawn } = await import('node:child_process')
  #|   return new Promise((resolve, reject) => {
  #|     const child = spawn(cmd, args, options)
  #|     const exit = new Promise((res) => {
  #|       child.once('exit', (code) => res({ code: code === null ? -1 : code }))
  #|     })
  #|     child.once('spawn', () => {
  #|       child.on('error', () => {})
  #|       resolve({ child, exit })
  #|     })
  #|     child.once('error', (err) => reject(err))
  #|   })
  #| }

///|
extern "js" fn child_prop(child : JsChildProcess, name : String) -> JsAny =
  #| (c, k) => c[k]

///|
extern "js" fn js_kill(child : JsChildProcess) -> Unit =
  #| (c) => {
  #|   try { c.kill() } catch {}
  #| }

///|
/// Spawn options: stdin/stdout piped, stderr inherited (server-side
/// logging, per the MCP spec), environment = parent env + `extra_env`.
extern "js" fn spawn_options(
  env_keys : Array[String],
  env_vals : Array[String],
) -> JsAny =
  #| (keys, vals) => {
  #|   const env = { ...globalThis.process.env }
  #|   for (let i = 0; i < keys.length; i++) env[keys[i]] = vals[i]
  #|   return { stdio: ['pipe', 'pipe', 'inherit'], env }
  #| }

///|
extern "js" fn readable_to_web(
  stream : JsAny,
) -> @js_async.Promise[@js_async.JsReadableStream] =
  #| async (stream) => {
  #|   const { Readable } = await import('node:stream')
  #|   return Readable.toWeb(stream)
  #| }

///|
extern "js" fn writable_to_web(stream : JsAny) -> @js_async.Promise[JsAny] =
  #| async (stream) => {
  #|   const { Writable } = await import('node:stream')
  #|   return Writable.toWeb(stream)
  #| }

///|
extern "js" fn stream_writer(ws : JsAny) -> JsStdinWriter =
  #| (ws) => ws.getWriter()

///|
/// One awaited write per `send`/`send_notification` (message + newline).
extern "js" fn writer_write(
  writer : JsStdinWriter,
  data : String,
) -> @js_async.Promise[Unit] =
  #| (w, s) => w.write(s)

///|
/// Fire-and-forget graceful close: end stdin (EOF signal), arm a kill
/// timer disarmed by the pre-registered exit promise. Runs entirely on the
/// JS side so the sync MoonBit `close()` cannot hang; writer-close
/// rejections (child already gone) are swallowed.
extern "js" fn graceful_close(
  writer : JsStdinWriter,
  child : JsChildProcess,
  exit : @js_async.Promise[ChildExit],
) -> Unit =
  #| (writer, child, exit) => {
  #|   const kill_timer = setTimeout(() => {
  #|     try { child.kill() } catch {}
  #|   }, 5000)
  #|   exit.then(() => clearTimeout(kill_timer)).catch(() => clearTimeout(kill_timer))
  #|   try { writer.close().catch(() => {}) } catch {}
  #| }

///|
pub struct StdioClientTransport {
  cmd : String
  args : Array[String]
  extra_env : Map[String, String]
  mut closed : Bool
  /// Buffered stdout reader; `Some` marks the transport as started.
  priv mut reader : &@io.Reader?
  /// Cancels the from_js copy coroutine and the underlying JS stream.
  priv mut stop_reader : () -> Unit
  priv mut child : JsChildProcess?
  priv mut writer : JsStdinWriter?
  priv mut exit : @js_async.Promise[ChildExit]?
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
    stop_reader: fn() { () },
    child: None,
    writer: None,
    exit: None,
  }
}

///|
/// Spawn the child process inside the given TaskGroup and build the
/// stdin/stdout bridges. Must be called before `send()` / `receive()`.
pub async fn StdioClientTransport::start(
  self : StdioClientTransport,
  group : @async.TaskGroup[Unit],
) -> Unit raise @types.TransportError {
  // The js bridge keeps no structured-concurrency state in `group`; the
  // child's lifetime is owned by the JS-side close choreography instead.
  ignore(group)
  if self.closed {
    raise @types.InvalidState("Cannot start a closed transport")
  }
  if self.reader is Some(_) {
    raise @types.InvalidState("Transport already started")
  }
  let started = js_start_child(
    self.cmd,
    self.args,
    spawn_options(env_keys(self.extra_env), env_vals(self.extra_env)),
  ).wait() catch {
    e =>
      raise @types.WriteError(
        "Failed to spawn process '\{self.cmd}': " + e.to_string(),
      )
  }
  // Fallible bridging first; on failure the child is killed so a partial
  // start never leaks a process.
  let stdout_web = readable_to_web(child_prop(started.child, "stdout")).wait() catch {
    e => {
      js_kill(started.child)
      raise @types.ReadError("Failed to bridge child stdout: " + e.to_string())
    }
  }
  let stdin_web = writable_to_web(child_prop(started.child, "stdin")).wait() catch {
    e => {
      js_kill(started.child)
      raise @types.WriteError("Failed to bridge child stdin: " + e.to_string())
    }
  }
  let rs = @js_async.ReadableStream::from_js(stdout_web)
  let reader : &@io.Reader = rs
  self.reader = Some(reader)
  self.stop_reader = fn() { rs.close() }
  self.child = Some(started.child)
  self.writer = Some(stream_writer(stdin_web))
  self.exit = Some(started.exit)
}

///|
/// Flatten a Map for the JS env-object builder (Map iteration preserves
/// insertion order, so keys and values stay aligned).
fn env_keys(extra : Map[String, String]) -> Array[String] {
  let keys = []
  for k, _ in extra {
    keys.push(k)
  }
  keys
}

///|
fn env_vals(extra : Map[String, String]) -> Array[String] {
  let vals = []
  for _, v in extra {
    vals.push(v)
  }
  vals
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
    Some(line) => {
      let message = line.trim().to_owned()
      if message.is_empty() {
        return self.receive()
      }
      Some(message)
    }
  }
}

///|
/// Send a JSON-RPC message to the child's stdin.
/// Validates the message, then writes it with a trailing newline in a
/// single awaited write (equivalent wire bytes to the native
/// buffered-write + flush).
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
  writer_write(writer, message + "\n").wait() catch {
    e =>
      raise @types.WriteError(
        "Failed to write to child stdin: " + e.to_string(),
      )
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
  writer_write(writer, json + "\n").wait() catch {
    e =>
      raise @types.WriteError("Failed to send notification: " + e.to_string())
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
/// 1. Close stdin (EOF signal to the child) via the JS-side choreography,
///    with a 5s kill timer disarmed by the child's exit.
/// 2. Cancel the stdout reader bridge.
/// 3. Mark the transport as closed.
pub fn StdioClientTransport::close(self : StdioClientTransport) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  match self.writer {
    Some(writer) =>
      match (self.child, self.exit) {
        (Some(child), Some(exit)) => graceful_close(writer, child, exit)
        _ => ()
      }
    None =>
      // Partial start (or never started): no stdin to close politely.
      match self.child {
        Some(child) => js_kill(child)
        None => ()
      }
  }
  self.writer = None
  self.child = None
  self.exit = None
  (self.stop_reader)()
  self.reader = None
}
