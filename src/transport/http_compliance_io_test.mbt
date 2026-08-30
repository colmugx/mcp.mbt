///| Http_compliance I/O configuration tests — native/wasm only.
/// On js, HttpTransport is an abort stub (see unimplemented_js.mbt), so these
/// tests are gated by moon.pkg targets.

///| =====================================================

///| HTTP Transport Configuration

///|
/// =====================================================
test "compliance: HttpTransport default port is 4240" {
  let transport = HttpTransport::HttpTransport()
  @debug.assert_eq(transport.port, 4240)
}

///|
test "compliance: HttpTransport default endpoint is /mcp" {
  let transport = HttpTransport::HttpTransport()
  @debug.assert_eq(transport.endpoint_path, "/mcp")
}

///|
test "compliance: HttpTransport supports custom port and path" {
  let transport = HttpTransport::HttpTransport(
    port=8080,
    endpoint_path="/api/mcp",
  )
  @debug.assert_eq(transport.port, 8080)
  @debug.assert_eq(transport.endpoint_path, "/api/mcp")
}

///| =====================================================

///| Request _meta Validation (real round trips)

///|
/// =====================================================

///|
/// Block until a TCP connect to `addr` succeeds; connection-refused just
/// means the HttpTransport server task has not bound its port yet. Distinct
/// name from sse_flush_io_test's `wait_for_listen` (both compile on native).
#cfg(target="native")
async fn await_http_listen(
  addr : @socket.Addr,
  timeout_ms? : Int = 5000,
) -> Unit {
  let deadline = @async.now() + timeout_ms.to_int64()
  while true {
    let probe = Some(@socket.Tcp::connect(addr)) catch { _ => None }
    match probe {
      Some(tcp) => {
        tcp.close()
        return
      }
      None =>
        if @async.now() > deadline {
          fail("server did not bind within \{timeout_ms}ms")
        } else {
          @async.sleep(20)
        }
    }
  }
}

///|
/// A request POST missing the required `params._meta` fields is malformed:
/// the server must answer HTTP 400 with an `Invalid params` (-32602)
/// JSON-RPC error body echoing the request id, and must not surface the
/// request to the application. A compliant POST still flows through.
#cfg(target="native")
async test "compliance: POST without required _meta gets 400 + -32602 with id" {
  let transport = HttpTransport::HttpTransport(port=47351, endpoint_path="/mcp")
  let client = HttpClientTransport::HttpClientTransport(
    "http://127.0.0.1:47351/mcp",
  )
  // The client derives every required header from the body; only `_meta` is
  // absent, so the header checks pass and the _meta gate is what fires.
  let missing_meta = "{\"jsonrpc\":\"2.0\",\"id\":41,\"method\":\"ping\",\"params\":{}}"
  let with_meta = "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"ping\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{}}}}"
  let final_response = "{\"jsonrpc\":\"2.0\",\"id\":42,\"result\":{\"ok\":true}}"
  @async.with_task_group(group => {
    group.spawn_bg(async fn() {
      match transport.receive_request() {
        Some((_message, reply)) => reply.put(final_response) catch { _ => () }
        None => fail("compliant request never reached the app")
      }
    })
    let server_task = group.spawn(async fn() {
      transport.start() catch {
        _ => ()
      }
    })
    await_http_listen(@socket.Addr::parse("127.0.0.1:47351"))
    try
      @async.with_timeout(3000, async fn() { client.send(missing_meta) })
    catch {
      e =>
        if e is @types.TransportError::HttpError(400, err_body) {
          let json = @json.parse(err_body) catch { _ => null }
          if json is Object(obj) {
            match obj.get("id") {
              Some(Number(n, ..)) => @debug.assert_eq(n.to_int(), 41)
              _ => fail("400 body does not echo the request id: \{err_body}")
            }
            match obj.get("error") {
              Some(Object(rpc_err)) => {
                match rpc_err.get("code") {
                  Some(Number(n, ..)) => @debug.assert_eq(n.to_int(), -32602)
                  _ => fail("400 body error code is not -32602: \{err_body}")
                }
                match rpc_err.get("message") {
                  Some(String(m)) => assert_true(m.contains("_meta"))
                  _ => fail("400 body has no error message: \{err_body}")
                }
              }
              _ => fail("400 body has no error object: \{err_body}")
            }
          } else {
            fail("400 body is not a JSON object: \{err_body}")
          }
        } else {
          fail("expected HttpError(400, ...), got: \{e}")
        }
    } noraise {
      _ => fail("missing-_meta POST unexpectedly succeeded")
    }
    // Compliant POST: reaches the app and returns its response verbatim.
    group.spawn_bg(async fn() { client.send(with_meta) catch { _ => () } })
    match @async.with_timeout_opt(3000, async fn() { client.receive() }) {
      Some(Some(resp)) => @debug.assert_eq(resp, final_response)
      _ => fail("compliant request never got its response")
    }
    server_task.cancel()
  })
}

///|
/// Raw POST carrying an explicit `Origin` header (HttpClientTransport never
/// sets one), returning `(status, body)` so the e2e below can probe the
/// origin gate directly.
#cfg(target="native")
async fn origin_probe_post(
  url : String,
  body : String,
  origin~ : String,
) -> (Int, String) {
  let body_bytes = @utf8.encode(body)
  let headers : @http.Headers = Default::default()
  headers["Content-Type"] = "application/json"
  headers["Content-Length"] = body_bytes.length().to_string()
  headers["MCP-Protocol-Version"] = @types.ProtocolVersion
  headers["Mcp-Method"] = "ping"
  headers["Origin"] = origin
  let client = @http.post_stream(url, headers~) catch {
    e => fail("origin probe POST failed: \{e}")
  }
  defer client.close()
  client.write(body_bytes) catch {
    e => fail("origin probe write failed: \{e}")
  }
  client.flush() catch {
    e => fail("origin probe flush failed: \{e}")
  }
  let response = client.end_request() catch {
    e => fail("origin probe got no response: \{e}")
  }
  let body_str = try {
    let b = client.read_all()
    b.text()
  } catch {
    _ => ""
  }
  (response.code, body_str)
}

///|
/// Unauthenticated servers still validate Origin (spec
/// basic/transports/streamable-http#security-endpoint): a cross-origin POST
/// is rejected with 403 before reaching the application, while a loopback
/// origin and a request without an Origin header (non-browser client) are
/// processed normally.
#cfg(target="native")
async test "compliance: unauthenticated server rejects cross-origin POST with 403" {
  let transport = HttpTransport::HttpTransport(port=47352, endpoint_path="/mcp")
  let client = HttpClientTransport::HttpClientTransport(
    "http://127.0.0.1:47352/mcp",
  )
  let with_meta = "{\"jsonrpc\":\"2.0\",\"id\":51,\"method\":\"ping\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{}}}}"
  let final_response = "{\"jsonrpc\":\"2.0\",\"id\":51,\"result\":{\"ok\":true}}"
  @async.with_task_group(group => {
    // Application side: serve the two requests that pass the origin gate
    // (the loopback-origin POST and the no-Origin POST). The cross-origin
    // POST must never surface here.
    group.spawn_bg(async fn() {
      for _ in 0..<2 {
        match transport.receive_request() {
          Some((_message, reply)) => reply.put(final_response) catch { _ => () }
          None => fail("origin-passing request never reached the app")
        }
      }
    })
    let server_task = group.spawn(async fn() {
      transport.start() catch {
        _ => ()
      }
    })
    await_http_listen(@socket.Addr::parse("127.0.0.1:47352"))
    // Cross-origin browser request: 403, never reaches the application.
    let (evil_code, evil_body) = origin_probe_post(
      "http://127.0.0.1:47352/mcp",
      with_meta,
      origin="https://evil.com",
    )
    @debug.assert_eq(evil_code, 403)
    assert_true(evil_body.contains("invalid_origin"))
    // Loopback origin on an arbitrary port: default policy allows it.
    let (loop_code, loop_body) = origin_probe_post(
      "http://127.0.0.1:47352/mcp",
      with_meta,
      origin="http://localhost:57123",
    )
    @debug.assert_eq(loop_code, 200)
    @debug.assert_eq(loop_body, final_response)
    // No Origin header at all: non-browser client, normal processing.
    group.spawn_bg(async fn() { client.send(with_meta) catch { _ => () } })
    match @async.with_timeout_opt(3000, async fn() { client.receive() }) {
      Some(Some(resp)) => @debug.assert_eq(resp, final_response)
      _ => fail("no-Origin request never got its response")
    }
    server_task.cancel()
  })
}
