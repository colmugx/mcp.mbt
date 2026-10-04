///|
async test "conformance: resource registration preserves definitions and multiple read contents" {
  let definition = @types.ResourceDefinition::from_json({
    "uri": "memo://1",
    "name": "memo",
    "title": "Memo",
    "icons": [],
    "annotations": {},
    "_meta": { "com.example/definition": false },
  })
  let template = @types.ResourceTemplateDefinition::from_json({
    "uriTemplate": "memo://{id}",
    "name": "memo",
    "title": "Memos",
    "icons": [],
    "_meta": {},
  })
  let contents : Array[Json] = [
    { "uri": "memo://1", "text": "hello", "_meta": {} },
    { "uri": "memo://2", "blob": "aGk=", "com.example/key": null },
  ]
  let result = @types.ResourceReadResult::from_json({
    "contents": Json::array(contents),
    "_meta": { "com.example/result": false },
  })
  let server = MCPServer::MCPServer("test", "1")
    .resource_definition(definition, (_context, _) => {
      Ok(@resource.ResourceReadOutcome::Complete(result))
    })
    .resource_template_definition(template)
  assert_eq(server.resource_registry.list_resources(), [definition])
  assert_eq(server.resource_registry.list_templates(), [template])
  let list_wire = @json.parse(
    handle_resources_list(server, @types.RequestId::Int(1)),
  )
  guard list_wire is { "result": { "resources": Array(resources), .. }, .. } else {
    fail("expected resource list")
  }
  assert_eq(resources, [definition.to_json()])
  let template_wire = @json.parse(
    handle_resources_templates_list(server, @types.RequestId::Int(1)),
  )
  guard template_wire
    is { "result": { "resourceTemplates": Array(templates), .. }, .. } else {
    fail("expected template list")
  }
  assert_eq(templates, [template.to_json()])
  let read_wire = @json.parse(
    handle_resources_read(
      server,
      @runtime.RequestContext::new(@types.RequestId::Int(2)),
      { "uri": "memo://1" },
    ),
  )
  guard read_wire is { "result": Object(fields), .. } else {
    fail("expected resource read result")
  }
  let decoded = @types.ResourceReadResult::from_json(Json::object(fields))
  assert_eq(decoded.contents.map(@types.ResourceContents::to_json), contents)
  assert_eq(
    decoded.metadata.meta.unwrap().get("com.example/result"),
    Some(false),
  )
  assert_eq(
    decoded.metadata.server_info(),
    Some({ "name": "test", "version": "1" }),
  )
  assert_eq(result.metadata.server_info(), None)
}
