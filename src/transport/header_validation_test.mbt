///|
fn mirror_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "tenant": { "type": "string", "x-mcp-header": "Tenant" },
      "nested": {
        "type": "object",
        "properties": {
          "count": { "type": "integer", "x-mcp-header": "Count" },
          "enabled": { "type": "boolean", "x-mcp-header": "Enabled" },
        },
      },
    },
  }
}

///|
test "mirrored headers compare exact nested paths case insensitive names and numeric integers" {
  let arguments : Json = {
    "tenant": "team",
    "nested": { "count": 42, "enabled": false },
  }
  assert_true(
    @transport.validate_tool_parameter_headers(mirror_schema(), arguments, [
      ("MCP-PARAM-TENANT", "team"),
      ("mcp-param-COUNT", "42.0"),
      ("Mcp-Param-Enabled", "false"),
    ])
    is Ok(_),
  )
  assert_true(
    @transport.validate_tool_parameter_headers(mirror_schema(), arguments, [
      ("Mcp-Param-Tenant", "team"),
      ("Mcp-Param-Count", "42"),
      ("Mcp-Param-Enabled", "false"),
    ])
    is Ok(_),
  )
}

///|
test "mirrored headers reject missing mismatched or duplicate recognized values" {
  let arguments : Json = {
    "tenant": "team",
    "nested": { "count": 42, "enabled": false },
  }
  for
    headers in [
      [("Mcp-Param-Tenant", "team"), ("Mcp-Param-Count", "42")],
      [
        ("Mcp-Param-Tenant", "other"),
        ("Mcp-Param-Count", "42"),
        ("Mcp-Param-Enabled", "false"),
      ],
      [
        ("Mcp-Param-Tenant", "team"),
        ("Mcp-Param-Count", "42.5"),
        ("Mcp-Param-Enabled", "false"),
      ],
      [
        ("Mcp-Param-Tenant", "team"),
        ("Mcp-Param-Count", "42"),
        ("Mcp-Param-Enabled", "False"),
      ],
      [
        ("Mcp-Param-Tenant", "team"),
        ("mcp-param-tenant", "team"),
        ("Mcp-Param-Count", "42"),
        ("Mcp-Param-Enabled", "false"),
      ],
    ] {
    assert_true(
      @transport.validate_tool_parameter_headers(
        mirror_schema(),
        arguments,
        headers,
      )
      is Err(_),
    )
  }
}

///|
test "mirrored absent and null arguments omit headers while unknown headers are ignored" {
  for
    arguments in [
      Json::object({}),
      Json::object({ "tenant": null, "nested": {} }),
    ] {
    assert_true(
      @transport.validate_tool_parameter_headers(mirror_schema(), arguments, [
        ("Mcp-Param-Unrecognized", "=?base64?invalid?="),
      ])
      is Ok(_),
    )
    assert_true(
      @transport.validate_tool_parameter_headers(mirror_schema(), arguments, [
        ("Mcp-Param-Tenant", ""),
      ])
      is Err(_),
    )
  }
  assert_true(
    @transport.validate_tool_parameter_headers(
      mirror_schema(),
      { "tenant": "" },
      [("Mcp-Param-Tenant", "")],
    )
    is Ok(_),
  )
}

///|
test "mirrored headers decode UTF8 sentinel values once and reject malformed encodings" {
  for value in ["世界", " padded ", "line1\nline2", "=?base64?literal?=", ""] {
    assert_true(
      @transport.validate_tool_parameter_headers(
        mirror_schema(),
        { "tenant": value },
        [("Mcp-Param-Tenant", @transport.encode_base64_sentinel(value))],
      )
      is Ok(_),
    )
  }
  for
    encoded in [
      "=?base64?invalid?=", "=?base64?/w==?=", " padded ", "line1\nline2", "世界",
    ] {
    assert_true(
      @transport.validate_tool_parameter_headers(
        mirror_schema(),
        { "tenant": encoded },
        [("Mcp-Param-Tenant", encoded)],
      )
      is Err(_),
    )
  }
}

///|
test "mirrored integer headers preserve safe range without truncation" {
  let fractional = @validation.parse_json("42.0000000000000000000000000000001")
  for
    (body, header) in [
      (fractional, "42"),
      (Json::number(42), "42.0000000000000000000000000000001"),
    ] {
    assert_true(
      @transport.validate_tool_parameter_headers(
        mirror_schema(),
        { "nested": { "count": body } },
        [("Mcp-Param-Count", header)],
      )
      is Err(_),
    )
  }
  for value in [9007199254740991.0, -9007199254740991.0, 2147483648.0] {
    assert_true(
      @transport.validate_tool_parameter_headers(
        mirror_schema(),
        { "nested": { "count": value } },
        [("Mcp-Param-Count", value.to_int64().to_string())],
      )
      is Ok(_),
    )
  }
  for value in [9007199254740992.0, 1.5] {
    assert_true(
      @transport.validate_tool_parameter_headers(
        mirror_schema(),
        { "nested": { "count": value } },
        [("Mcp-Param-Count", value.to_string())],
      )
      is Err(_),
    )
  }
}
