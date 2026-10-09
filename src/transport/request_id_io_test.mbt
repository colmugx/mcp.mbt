///|
async test "HTTP compatibility routing isolates large and string ids under reversed replies" {
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
          ).unwrap()
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
