///|
async test "e2e/http: HTTP compatibility routing isolates large and string ids under reversed replies" {
  let transport = @transport.HttpTransport::HttpTransport(port=47397)
  let literals = [
    "9007199254740992", "9007199254740993", "\"9007199254740993\"", "4.2e1",
  ]
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = group.spawn(() => {
        transport.start() catch {
          error => if !@async.is_being_cancelled() { raise error }
        }
      })
      await_http_listen(@socket.Addr::parse("127.0.0.1:47397"))
      group.spawn_bg(() => {
        let ids : Array[@types.RequestId] = []
        for _ in 0..<literals.length() {
          let message = transport.receive().unwrap()
          let request = @types.JsonRpcRequest::from_json(
            @validation.parse_json(message),
          )
          ids.push(request.id)
        }
        for index = ids.length() - 1; index >= 0; index = index - 1 {
          let id = if ids[index] == @types.RequestId::Int(42) {
            "42"
          } else {
            ids[index].to_json_string()
          }
          transport.send(
            "{\"jsonrpc\":\"2.0\",\"id\":" +
            id +
            ",\"result\":{\"resultType\":\"complete\"}}",
          )
        }
      })
      let tasks : Array[@async.Task[Unit]] = []
      for literal in literals {
        tasks.push(
          group.spawn(() => {
            let client = @transport.HttpClientTransport::HttpClientTransport(
              "http://127.0.0.1:47397/mcp",
            )
            defer client.close()
            let request = "{\"jsonrpc\":\"2.0\",\"id\":" +
              literal +
              ",\"method\":\"tools/list\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{}}}}"
            client.send(request)
            let response = @validation.parse_json(client.receive().unwrap())
            guard response is Object(fields) && fields.get("id") is Some(id) else {
              fail("missing response id")
            }
            assert_eq(
              @types.RequestId::from_json(id),
              @types.RequestId::from_json(@validation.parse_json(literal)),
            )
            try
              client.send(
                "{\"jsonrpc\":\"2.0\",\"id\":" +
                literal +
                ",\"method\":\"tools/list\",\"params\":{}}",
              )
            catch {
              @types.HttpError(400, body) => {
                let rejection = @validation.parse_json(body)
                guard rejection is Object(error) &&
                  error.get("id") is Some(echoed) else {
                  fail("missing rejection id")
                }
                assert_eq(
                  @types.RequestId::from_json(echoed).to_json_string(),
                  literal,
                )
              }
              error => fail("unexpected rejection: \{Repr(error)}")
            } noraise {
              _ => fail("missing metadata must be rejected")
            }
          }),
        )
      }
      for task in tasks {
        task.wait()
      }
      server.cancel()
    })
  })
}

///|
async test "e2e/http: response and batch POST bodies are rejected before dispatch" {
  let transport = @transport.HttpTransport::HttpTransport(port=47403)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = group.spawn(() => {
        transport.start() catch {
          error => if !@async.is_being_cancelled() { raise error }
        }
      })
      await_http_listen(@socket.Addr::parse("127.0.0.1:47403"))
      for
        body in [
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}", "[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}]",
        ] {
        let (status, response) = origin_probe_post(
          "http://127.0.0.1:47403/mcp",
          body,
          origin="http://localhost",
        )
        assert_eq(status, 400)
        assert_true(
          @validation.parse_json(response)
          is { "error": { "code": -32600, .. }, .. },
        )
      }
      let client = @transport.HttpClientTransport::HttpClientTransport(
        "http://127.0.0.1:47403/mcp",
      )
      defer client.close()
      let valid = "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"ping\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{}}}}"
      let sent = group.spawn(() => client.send(valid))
      let request = transport.receive_authenticated_request().unwrap()
      assert_eq(request.message, valid)
      request.reply.put("{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{}}")
      sent.wait()
      server.cancel()
    })
  })
}
