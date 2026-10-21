///|
async test "e2e/http: MRTR maximum rounds bounds exchanges without a final unconsumable user interaction" {
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
      try client.send_with_mrtr(request, max_rounds=0) catch {
        @types.InternalError(_) => ()
        error => raise error
      } noraise {
        _ => fail("expected protocol error")
      }
      assert_true(requests.is_empty())
      try client.send_with_mrtr(request, max_rounds=3) catch {
        @types.InternalError(message) =>
          assert_true(message.contains("max rounds"))
        _ => fail("non-completing MRTR must be bounded")
      } noraise {
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

///|
async test "e2e/http: error fidelity, forbidden duplex requests and final SSE ownership" {
  let server = @socket.TcpServer::TcpServer(
    @socket.Addr::parse("127.0.0.1:47401"),
    reuse_addr=true,
  )
  defer server.close()
  let release : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let serving = group.spawn(() => {
        for index in 0..<5 {
          let (conn, _) = server.accept()
          defer conn.close()
          let head = conn.read_until("\r\n\r\n").unwrap()
          let body = if head.to_lower().contains("transfer-encoding: chunked") {
            era_read_chunked_body(conn)
          } else {
            @utf8.decode(conn.read_exactly(era_content_length(head)))
          }
          guard @validation.parse_json(body) is { "id": id, .. } else {
            fail("missing request id")
          }
          let peer_error : Json = {
            "jsonrpc": "2.0",
            "id": id,
            "error": {
              "code": @validation.parse_json("-9007199254740993"),
              "message": "peer error",
              "data": null,
              "vendor": false,
            },
          }
          let response = match index {
            0 =>
              era_http_response(
                "400 Bad Request",
                "application/json",
                peer_error.stringify(),
              )
            1 =>
              era_http_response(
                "400 Bad Request", "application/json", "{\"jsonrpc\":\"2.0\",\"id\":999,\"error\":{\"code\":-32021,\"message\":\"wrong id\"}}",
              )
            2 =>
              era_http_response(
                "200 OK", "application/json", "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"sampling/createMessage\",\"params\":{}}",
              )
            3 =>
              "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\ndata: " +
              ({ "jsonrpc": "2.0", "id": id, "result": {} } : Json).stringify() +
              "\n\n"
            _ =>
              era_http_response(
                "200 OK", "text/event-stream", "data: {\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"sampling/createMessage\",\"params\":{}}\n\n",
              )
          }
          conn.write(@utf8.encode(response))
          if index == 3 {
            release.get()
          }
        }
      })
      for index in 0..<5 {
        let client = MCPClient::MCPClient(
          name="test",
          version="1",
          transport=@transport.AnyTransport::HttpClient(
            @transport.HttpClientTransport::HttpClientTransport(
              "http://127.0.0.1:47401/",
            ),
          ),
        )
        defer client.close()
        let result = Ok(
          client.send_request(
            build_tools_list_request(
              client.next_request_id(),
              client.request_meta(),
            ),
          ),
        ) catch {
          @types.MCPError::_ as error => Err(error)
          error => raise error
        }
        match (index, result) {
          (0, Err(error)) => {
            assert_eq(
              error.to_error_code().to_json().stringify(),
              "-9007199254740993",
            )
            assert_eq(
              error.to_jsonrpc_error(),
              (
                {
                  "code": @validation.parse_json("-9007199254740993"),
                  "message": "peer error",
                  "data": null,
                  "vendor": false,
                } : Json),
            )
          }
          (1, Err(@types.InvalidRequest(_))) => ()
          (2 | 4, Err(@types.InternalError(message))) =>
            assert_true(message.contains("independent"))
          (3, _) => release.put(())
          _ => fail("unexpected HTTP result: \{index}")
        }
      }
      serving.wait()
    })
  })
}

///|
async test "e2e/http: registered remote schema contracts and missing capability status survive the wire" {
  let resources : Map[String, Json] = {
    "urn:test:positive": { "type": "integer", "minimum": 1 },
  }
  let definition = @types.ToolDefinition::new(
    "remote",
    {
      "type": "object",
      "properties": { "count": { "$ref": "urn:test:positive" } },
      "required": ["count"],
      "unevaluatedProperties": false,
    },
    output_schema={ "$ref": "urn:test:positive" },
  )
  let calls = Ref(0)
  let output = Ref((1 : Json))
  let sdk = @server.MCPServer::MCPServer("test", "1")
    .tool_definition(
      definition,
      (_, _) => {
        calls.val += 1
        Ok(
          @server.ToolCallOutcome::Complete(
            @types.ToolResult::structured(output.val),
          ),
        )
      },
      schema_resources=resources,
    )
    .tool_definition(
      @types.ToolDefinition::new("needs-input", { "type": "object" }),
      (_, _) => {
        Ok(
          @server.ToolCallOutcome::InputRequired(
            input_requests={
              "form": {
                method_name: @types.ElicitationCreate,
                params: {
                  "message": "Confirm",
                  "requestedSchema": { "type": "object", "properties": {} },
                },
              },
            },
            state={},
          ),
        )
      },
    )
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let serving = group.spawn(() => {
        sdk.run_http(port=47402) catch {
          error => if !@async.is_being_cancelled() { raise error }
        }
      })
      let deadline = @async.now() + 2000
      while true {
        let probe = Some(
          @socket.Tcp::connect(@socket.Addr::parse("127.0.0.1:47402")),
        ) catch {
          _ => None
        }
        if probe is Some(probe) {
          probe.close()
          break
        }
        if @async.now() > deadline {
          fail("SDK HTTP server did not bind")
        }
        @async.sleep(5)
      }
      let client = MCPClient::MCPClient(
        name="test",
        version="1",
        transport=@transport.AnyTransport::HttpClient(
          @transport.HttpClientTransport::HttpClientTransport(
            "http://127.0.0.1:47402/mcp",
          ),
        ),
      )
      defer client.close()
      ignore(client.call_tool("remote", arguments="{\"count\":1}"))
      try client.call_tool("remote", arguments="{\"count\":0}") catch {
        @types.MCPError::_ as error =>
          assert_eq(error.to_error_code().as_int(), Some(-32602))
        _ => fail("invalid remote-schema input reached handler")
      } noraise {
        _ => fail("invalid remote-schema input reached handler")
      }
      assert_eq(calls.val, 1)
      output.val = 0
      try client.call_tool("remote", arguments="{\"count\":1}") catch {
        @types.MCPError::_ as error =>
          assert_eq(error.to_error_code().as_int(), Some(-32603))
        _ => fail("invalid structured output published")
      } noraise {
        _ => fail("invalid structured output published")
      }
      try client.call_tool("needs-input") catch {
        @types.MCPError::_ as error =>
          assert_eq(error.to_error_code().as_int(), Some(-32021))
        _ => fail("missing capability was not returned as a peer error")
      } noraise {
        _ => fail("missing capability was not returned as a peer error")
      }
      let raw = @transport.HttpClientTransport::HttpClientTransport(
        "http://127.0.0.1:47402/mcp",
      )
      defer raw.close()
      let request = build_tools_call_request(
        90,
        "needs-input",
        client.request_meta(),
      )
      try raw.send(request) catch {
        @types.HttpError(400, body) =>
          assert_true(
            @validation.parse_json(body)
            is { "error": { "code": -32021, .. }, .. },
          )
        error => raise error
      } noraise {
        _ => fail("missing capability must use HTTP 400")
      }
      serving.cancel()
    })
  })
}
