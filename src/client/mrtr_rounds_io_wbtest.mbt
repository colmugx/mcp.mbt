///|
async test "MRTR maximum rounds bounds exchanges without a final unconsumable user interaction" {
  let server = @socket.TcpServer::TcpServer(
    @socket.Addr::parse("127.0.0.1:47396"),
    reuse_addr=true,
  )
  defer server.close()
  let requests : Array[Json] = []
  let interactions = Ref(0)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let serving = group.spawn(() => {
        while true {
          let (conn, _) = server.accept()
          defer conn.close()
          let head = conn.read_until("\r\n\r\n").unwrap()
          let body = if head.to_lower().contains("transfer-encoding: chunked") {
            era_read_chunked_body(conn)
          } else {
            @utf8.decode(conn.read_exactly(era_content_length(head)))
          }
          let request = @validation.parse_json(body)
          requests.push(request)
          guard request is { "id": id, .. } else { fail("request has no id") }
          let response : Json = {
            "jsonrpc": "2.0",
            "id": id,
            "result": {
              "resultType": "input_required",
              "requestState": "state",
              "inputRequests": {
                "form": {
                  "method": "elicitation/create",
                  "params": {
                    "message": "Confirm",
                    "requestedSchema": { "type": "object", "properties": {} },
                  },
                },
              },
            },
          }
          conn.write(
            @utf8.encode(
              era_http_response(
                "200 OK",
                "application/json",
                response.stringify(),
              ),
            ),
          )
        }
      })
      let client = MCPClient::MCPClient(
        name="test",
        version="1",
        transport=@transport.AnyTransport::HttpClient(
          @transport.HttpClientTransport::HttpClientTransport(
            "http://127.0.0.1:47396/",
          ),
        ),
      ).on_elicitation(fn(_) {
        interactions.val += 1
        Ok(@types.ElicitationResult::new(@types.Cancel))
      })
      defer client.close()
      let request = build_tools_call_request(
        client.next_request_id(),
        "confirm",
        client.request_meta(),
        arguments="{\"value\":1}",
      )
      assert_true(
        client.send_with_mrtr(request, max_rounds=0)
        is Err(@types.InternalError(_)),
      )
      assert_true(requests.is_empty())
      match client.send_with_mrtr(request, max_rounds=3) {
        Err(@types.InternalError(message)) =>
          assert_true(message.contains("max rounds"))
        _ => fail("non-completing MRTR must be bounded")
      }
      assert_eq(requests.length(), 3)
      assert_eq(interactions.val, 2)
      for index, request in requests {
        guard request
          is {
            "id": Number(id, ..),
            "params": {
              "name": String("confirm"),
              "arguments": { "value": Number(1, ..), .. },
              ..
            } as params,
            ..
          } else {
          fail("retry lost original operation")
        }
        assert_eq(id, (index + 1).to_double())
        if index > 0 {
          assert_true(
            params
            is {
              "requestState": String("state"),
              "inputResponses": {
                "form": { "action": String("cancel"), .. },
                ..
              },
              ..
            },
          )
        }
      }
      serving.cancel()
    })
  })
}
