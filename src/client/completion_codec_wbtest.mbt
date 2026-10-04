///|
test "completion resource request uses uri and includes context arguments" {
  let wire = @json.parse(
    build_completion_reference_request(
      1,
      {},
      @types.CompletionReference::resource("memo://{id}"),
      argument_name="id",
      argument_value="a",
      context_arguments={ "locale": "zh" },
    ),
  )
  guard wire is { "params": params, .. } else {
    fail("expected completion params")
  }
  let params = @types.CompleteRequestParams::from_json(params)
  assert_eq(
    params.reference,
    @types.CompletionReference::resource("memo://{id}"),
  )
  assert_eq(
    params.context.unwrap().arguments.unwrap().get("locale"),
    Some("zh"),
  )
}

///|
test "completion client codec rejects nonstring suggestions and retains metadata" {
  match parse_completion_result({ "completion": { "values": [1] } }) {
    Err(@types.InvalidParams(_)) => ()
    _ => fail("invalid suggestions must not be silently dropped")
  }
  let result = parse_completion_result({
    "completion": { "values": ["x"] },
    "_meta": { "trace": "kept" },
    "future": false,
  })
  guard result is Ok(result) else { fail("expected valid completion") }
  assert_eq(
    result.metadata.meta.unwrap().get("trace"),
    Some(Json::string("kept")),
  )
  assert_eq(
    result.metadata.extensions.get("future"),
    Some(Json::boolean(false)),
  )
}
