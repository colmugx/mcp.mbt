struct HttpPendingRequest {
  message : String
  reply_queue : @async.Queue[HttpResponse]
}

struct HttpResponse {
  body : String
  use_sse : Bool
}

pub struct HttpTransport {
  port : Int
  endpoint_path : String
  pending_requests : @async.Queue[HttpPendingRequest]
  mut current_reply_queue : @async.Queue[HttpResponse]?
  session_id : String?
}

pub fn HttpTransport::new(
  port? : Int = 4240,
  endpoint_path? : String = "/mcp",
) -> HttpTransport {
  {
    port,
    endpoint_path,
    pending_requests: @async.Queue::new(kind=Unbounded),
    current_reply_queue: None,
    session_id: None,
  }
}

pub async fn HttpTransport::start(
  self : HttpTransport,
) -> Unit raise @types.TransportError {
  let addr = "127.0.0.1:" + self.port.to_string()
  let _ = @stdio.stderr.write(
    "[HttpTransport] Binding to " + addr + self.endpoint_path + "\n",
  ) catch {
    _ => ()
  }
  let server = @http.Server::new(@socket.Addr::parse(addr), reuse_addr=true) catch {
    e => raise @types.WriteError("Failed to create server: " + e.to_string())
  }
  let _ = @stdio.stderr.write("[HttpTransport] Streamable HTTP server ready\n") catch {
    _ => ()
  }
  server.run_forever(async fn(req, body, conn) {
    if req.path != self.endpoint_path {
      conn.send_response(404, "Not Found")
      conn.end_response()
      return
    }
    let _ = @stdio.stderr.write("[HttpTransport] Request to " + req.path + "\n") catch {
      _ => ()
    }
    match req.meth {
      Post => {
        let message = body.read_all().text() catch {
            _ => {
              conn.send_response(400, "Bad Request")
              conn.end_response()
              return
            }
          }
        let reply_queue = @async.Queue::new(kind=Blocking(1))
        try {
          self.pending_requests.put({ message, reply_queue })
          let response = reply_queue.get()
          if response.use_sse {
            conn.send_response(200, "OK", extra_headers={
              "Content-Type": "text/event-stream",
              "Cache-Control": "no-cache",
              "Connection": "keep-alive",
            })
            conn.flush()
            conn.write("data: " + response.body + "\n\n")
            conn.flush()
            conn.end_response()
          } else {
            conn.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            conn.write(response.body)
            conn.end_response()
          }
        } catch {
          _ => {
            conn.send_response(500, "Internal Server Error")
            conn.end_response()
          }
        }
      }
      Get => {
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          "Connection": "keep-alive",
        })
        conn.flush()
        while true {
          @async.sleep(1000000)
        }
      }
      _ => {
        conn.send_response(405, "Method Not Allowed")
        conn.end_response()
      }
    }
  }) catch {
    e => raise @types.WriteError("Server stopped: " + e.to_string())
  }
}

pub async fn HttpTransport::receive(
  self : HttpTransport,
) -> String? raise @types.TransportError {
  try {
    let req = self.pending_requests.get()
    self.current_reply_queue = Some(req.reply_queue)
    Some(req.message)
  } catch {
    e => raise @types.ReadError(e.to_string())
  }
}

pub async fn HttpTransport::send(
  self : HttpTransport,
  message : String,
) -> Unit raise @types.TransportError {
  match self.current_reply_queue {
    Some(q) =>
      try {
        q.put({ body: message, use_sse: false })
        self.current_reply_queue = None
      } catch {
        e => raise @types.WriteError(e.to_string())
      }
    None => raise @types.InvalidState("No pending request to reply to")
  }
}

pub fn HttpTransport::send_event(
  self : HttpTransport,
  event_type~ : String,
  data~ : String,
) -> Unit {
  ignore(event_type)
  ignore(data)
  ignore(self)
}

pub fn HttpTransport::supports_streaming(_self : HttpTransport) -> Bool {
  true
}

pub fn HttpTransport::close(self : HttpTransport) -> Unit {
  ignore(self)
}
