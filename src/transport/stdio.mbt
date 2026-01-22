pub struct StdioTransport {
  mut closed : Bool
} derive(Show)

pub fn StdioTransport::new() -> StdioTransport {
  { closed: false }
}

pub async fn StdioTransport::receive(
  self : StdioTransport,
) -> String? raise @types.TransportError {
  if self.closed {
    return None
  }

  let line_result = @stdio.stdin.read_until("\n") catch {
    e => raise @types.ReadError("Failed to read from stdin: " + e.to_string())
  }
  match line_result {
    None => {
      self.closed = true
      None
    }
    Some(line_view) => {
      let line = line_view.to_string()
      let message = line.trim().to_string()

      if message.is_empty() {
        return self.receive()
      }
      Some(message)
    }
  }
}

pub async fn StdioTransport::send(
  self : StdioTransport,
  message : String,
) -> Unit raise @types.TransportError {
  if self.closed {
    raise @types.InvalidState("Cannot send on closed transport")
  }

  match validate_jsonrpc_message(message) {
    Err(e) => raise @types.WriteError("Invalid JSON-RPC message: " + e.message())
    Ok(_) => ()
  }

  @stdio.stdout.write(message + "\n") catch {
    e => raise @types.WriteError("Failed to write to stdout: " + e.to_string())
  }
}

pub fn StdioTransport::send_event(
  _self : StdioTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  ignore(event_type)
  ignore(data)
  ()
}

pub fn StdioTransport::supports_streaming(_self : StdioTransport) -> Bool {
  false
}

pub fn StdioTransport::close(self : StdioTransport) -> Unit {
  if not(self.closed) {
    self.closed = true
  }
}
