///| Era-routing connection tests over a raw-socket fake HTTP server.
/// The fake server records every JSON-RPC method it receives and answers
/// like a legacy-only (2025-11-25) or modern (2026-07-28) server, so each
/// test can assert which first message a given era sends.

///|
/// Extract the `method` field of a single-line JSON-RPC body; "" when absent.
fn era_jsonrpc_method(body : String) -> String {
  let json = @json.parse(body) catch { _ => return "" }
  if json is Object(obj) {
    match obj.get("method") {
      Some(String(m)) => m
      _ => ""
    }
  } else {
    ""
  }
}

///|
/// Parse `Content-Length` out of an HTTP request head (0 when absent).
fn era_content_length(head : String) -> Int {
  let lowered = head.to_lower()
  let marker = "content-length:"
  let start = match lowered.find(marker) {
    Some(s) => s
    None => return 0
  }
  let value = lowered[start + marker.length():].trim()
  let mut n = 0
  for c in value {
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
    } else {
      break
    }
  }
  n
}

///|
fn era_http_response(
  status : String,
  content_type : String,
  body : String,
) -> String {
  "HTTP/1.1 " +
  status +
  "\r\nContent-Type: " +
  content_type +
  "\r\nContent-Length: " +
  body.length().to_string() +
  "\r\nConnection: close\r\n\r\n" +
  body
}

///|
/// Parse a small hex chunk-size line (0 on any parse trouble).
fn era_hex_size(line : String) -> Int {
  let mut n = 0
  for c in line.trim() {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      return n
    }
    n = n * 16 + d
  }
  n
}

///|
/// Read a chunked request body (the legacy client posts with
/// `Transfer-Encoding: chunked` instead of `Content-Length`).
async fn era_read_chunked_body(conn : @socket.Tcp) -> String {
  let parts : Array[String] = []
  while true {
    let size_line = match conn.read_until("\r\n") {
      Some(l) => l
      None => break
    }
    let size = era_hex_size(size_line)
    if size == 0 {
      break
    }
    let data : Bytes? = Some(conn.read_exactly(size)) catch { _ => None }
    let data = match data {
      Some(d) => d
      None => break
    }
    let _ = conn.read_exactly(2) catch { _ => b"" } // chunk-terminating CRLF
    parts.push(@utf8.decode(data) catch { _ => "" })
  }
  parts.join("")
}

///|
/// Answer one POST per connection like an era-specific server:
/// - legacy-only: `initialize` succeeds, `server/discover` gets a 422
///   "expect initialize" rejection (the classic 2025-11-25 server behavior);
/// - modern: `server/discover` succeeds with capabilities.
/// Notifications get 202. Every non-empty method is recorded in `methods`.
async fn era_fake_handle_conn(
  conn : @socket.Tcp,
  legacy_only : Bool,
  methods : Array[String],
) -> Unit {
  let head = match conn.read_until("\r\n\r\n") {
    Some(h) => h
    None => return
  }
  let len = era_content_length(head)
  let body = if head.to_lower().contains("transfer-encoding: chunked") {
    era_read_chunked_body(conn)
  } else if len > 0 {
    @utf8.decode(conn.read_exactly(len)) catch {
      _ => ""
    }
  } else {
    ""
  }
  let rpc_method = era_jsonrpc_method(body)
  if rpc_method != "" {
    methods.push(rpc_method)
  }
  let response : String = match rpc_method {
    "initialize" =>
      era_http_response(
        "200 OK", "application/json", "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"serverInfo\":{\"name\":\"era-fake\",\"version\":\"0.1\"}}}",
      )
    "server/discover" =>
      if legacy_only {
        era_http_response(
          "422 Unprocessable Entity", "text/plain", "Unexpected message, expect initialize request",
        )
      } else {
        era_http_response(
          "200 OK", "application/json", "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"tools\":{\"listChanged\":false}}}}",
        )
      }
    _ => era_http_response("202 Accepted", "application/json", "")
  }
  conn.write(response) catch {
    _ => ()
  }
}

///|
/// Serve connections sequentially until the task is cancelled.
async fn era_fake_server(
  server : @socket.TcpServer,
  legacy_only : Bool,
  methods : Array[String],
) -> Unit {
  while true {
    let (conn, _addr) = server.accept()
    era_fake_handle_conn(conn, legacy_only, methods)
    conn.close()
  }
}

///|
async test "era=Legacy connect_http sends initialize first, never discover" {
  let server = try! @socket.TcpServer::TcpServer(
    @socket.Addr::parse("127.0.0.1:47361"),
    reuse_addr=true,
  )
  defer server.close()
  let methods : Array[String] = []
  @async.with_task_group(group => {
    let server_task = group.spawn(async fn() {
      era_fake_server(server, true, methods)
    })
    match
      MCPClient::connect_http(
        url="http://127.0.0.1:47361/",
        name="era-test",
        version="0.1",
        era=Legacy,
      ) {
      Ok(client) => {
        assert_true(methods.length() > 0)
        @debug.assert_eq(methods[0], "initialize")
        assert_false(methods.contains("server/discover"))
        assert_true(client.backend is Legacy(_))
        client.close()
      }
      Err(e) => fail("era=Legacy connect failed: \{e.message()}")
    }
    server_task.cancel()
  })
}

///|
async test "era=Modern connect_http: legacy fallback forbidden, modern ok" {
  // Legacy-only server: the 422 probe rejection must surface as an error
  // naming the era=Modern prohibition and the original 422 cause.
  let legacy_server = try! @socket.TcpServer::TcpServer(
    @socket.Addr::parse("127.0.0.1:47362"),
    reuse_addr=true,
  )
  defer legacy_server.close()
  let legacy_methods : Array[String] = []
  @async.with_task_group(group => {
    let server_task = group.spawn(async fn() {
      era_fake_server(legacy_server, true, legacy_methods)
    })
    match
      MCPClient::connect_http(
        url="http://127.0.0.1:47362/",
        name="era-test",
        version="0.1",
        era=Modern,
      ) {
      Ok(_) => fail("era=Modern unexpectedly connected to a legacy-only server")
      Err(e) => {
        let msg = e.message()
        assert_true(msg.contains("era=Modern forbids legacy fallback"))
        assert_true(msg.contains("422"))
      }
    }
    server_task.cancel()
  })
  // Modern server: era=Modern connects through the probe as usual.
  let modern_server = try! @socket.TcpServer::TcpServer(
    @socket.Addr::parse("127.0.0.1:47363"),
    reuse_addr=true,
  )
  defer modern_server.close()
  let modern_methods : Array[String] = []
  @async.with_task_group(group => {
    let server_task = group.spawn(async fn() {
      era_fake_server(modern_server, false, modern_methods)
    })
    match
      MCPClient::connect_http(
        url="http://127.0.0.1:47363/",
        name="era-test",
        version="0.1",
        era=Modern,
      ) {
      Ok(client) => {
        @debug.assert_eq(modern_methods[0], "server/discover")
        assert_true(client.backend is Modern)
        client.close()
      }
      Err(e) =>
        fail("era=Modern connect to modern server failed: \{e.message()}")
    }
    server_task.cancel()
  })
}

///|
async test "era default matches Auto: probe modern, fall back on legacy" {
  // No era passed on a modern server: probe + modern backend (现状).
  let modern_server = try! @socket.TcpServer::TcpServer(
    @socket.Addr::parse("127.0.0.1:47364"),
    reuse_addr=true,
  )
  defer modern_server.close()
  let modern_methods : Array[String] = []
  @async.with_task_group(group => {
    let server_task = group.spawn(async fn() {
      era_fake_server(modern_server, false, modern_methods)
    })
    match
      MCPClient::connect_http(
        url="http://127.0.0.1:47364/",
        name="era-test",
        version="0.1",
      ) {
      Ok(client) => {
        @debug.assert_eq(modern_methods[0], "server/discover")
        assert_true(client.backend is Modern)
        client.close()
      }
      Err(e) =>
        fail("default-era connect to modern server failed: \{e.message()}")
    }
    match
      MCPClient::connect_http(
        url="http://127.0.0.1:47364/",
        name="era-test",
        version="0.1",
        era=Auto,
      ) {
      Ok(client) => {
        assert_true(client.backend is Modern)
        client.close()
      }
      Err(e) => fail("era=Auto connect to modern server failed: \{e.message()}")
    }
    server_task.cancel()
  })
  // No era passed on a legacy-only server: silent fallback preserved (现状).
  let legacy_server = try! @socket.TcpServer::TcpServer(
    @socket.Addr::parse("127.0.0.1:47365"),
    reuse_addr=true,
  )
  defer legacy_server.close()
  let legacy_methods : Array[String] = []
  @async.with_task_group(group => {
    let server_task = group.spawn(async fn() {
      era_fake_server(legacy_server, true, legacy_methods)
    })
    match
      MCPClient::connect_http(
        url="http://127.0.0.1:47365/",
        name="era-test",
        version="0.1",
      ) {
      Ok(client) => {
        @debug.assert_eq(legacy_methods[0], "server/discover")
        @debug.assert_eq(legacy_methods[1], "initialize")
        assert_true(client.backend is Legacy(_))
        client.close()
      }
      Err(e) =>
        fail("default-era connect to legacy server failed: \{e.message()}")
    }
    server_task.cancel()
  })
}

///|
async test "MCPHost::connect_http passes era through" {
  let server = try! @socket.TcpServer::TcpServer(
    @socket.Addr::parse("127.0.0.1:47366"),
    reuse_addr=true,
  )
  defer server.close()
  let methods : Array[String] = []
  @async.with_task_group(group => {
    let server_task = group.spawn(async fn() {
      era_fake_server(server, true, methods)
    })
    let host = MCPHost::MCPHost(name="host", version="0.1")
    match
      host.connect_http(
        name="legacy",
        url="http://127.0.0.1:47366/",
        era=Legacy,
      ) {
      Ok(_) => {
        assert_true(methods.length() > 0)
        @debug.assert_eq(methods[0], "initialize")
      }
      Err(e) => fail("host era=Legacy connect failed: \{e.message()}")
    }
    match
      host.connect_http(
        name="modern",
        url="http://127.0.0.1:47366/",
        era=Modern,
      ) {
      Ok(_) =>
        fail("host era=Modern unexpectedly connected to a legacy-only server")
      Err(e) =>
        assert_true(e.message().contains("era=Modern forbids legacy fallback"))
    }
    host.close_all()
    server_task.cancel()
  })
}
