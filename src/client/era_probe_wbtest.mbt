///| Tests for era probing: modern-error recognition, verdict classification,
/// and legacy `_meta` rewriting.

///|
test "parse_jsonrpc_error parses -32022 with supported/requested" {
  let body = "{\"error\":{\"code\":-32022,\"message\":\"unsupported\",\"data\":{\"supported\":[\"2026-07-28\"],\"requested\":\"2025-11-25\"}}}"
  match parse_jsonrpc_error(body) {
    Some(@types.UnsupportedProtocolVersion(msg, supported~, requested~)) => {
      @debug.assert_eq(msg, "unsupported")
      @debug.assert_eq(supported, ["2026-07-28"])
      @debug.assert_eq(requested, "2025-11-25")
    }
    _ => fail("expected UnsupportedProtocolVersion")
  }
}

///|
test "parse_jsonrpc_error parses -32021 requiredCapabilities" {
  let body = "{\"error\":{\"code\":-32021,\"message\":\"need caps\",\"data\":{\"requiredCapabilities\":[\"elicitation\"]}}}"
  match parse_jsonrpc_error(body) {
    Some(@types.MissingRequiredClientCapability(msg, required~)) => {
      @debug.assert_eq(msg, "need caps")
      @debug.assert_eq(required, ["elicitation"])
    }
    _ => fail("expected MissingRequiredClientCapability")
  }
}

///|
test "parse_jsonrpc_error parses -32020 and ignores other codes" {
  match
    parse_jsonrpc_error(
      "{\"error\":{\"code\":-32020,\"message\":\"bad header\"}}",
    ) {
    Some(@types.HeaderMismatch(msg)) => @debug.assert_eq(msg, "bad header")
    _ => fail("expected HeaderMismatch")
  }
  @debug.assert_eq(
    parse_jsonrpc_error("{\"error\":{\"code\":-32601,\"message\":\"x\"}}"),
    None,
  )
  @debug.assert_eq(parse_jsonrpc_error("not json"), None)
}

///|
test "classify_probe_error: direct modern error surfaces" {
  let err = @types.HeaderMismatch("bad header")
  match classify_probe_error(err) {
    ModernError(e) => @debug.assert_eq(e, err)
    _ => fail("expected ModernError")
  }
}

///|
test "classify_probe_error: HTTP 400 carrying modern error surfaces" {
  let body = "{\"error\":{\"code\":-32021,\"message\":\"need caps\",\"data\":{\"requiredCapabilities\":[\"roots\"]}}}"
  match
    classify_probe_error(@types.TransportError(@types.HttpError(400, body))) {
    ModernError(@types.MissingRequiredClientCapability(_, required~)) =>
      @debug.assert_eq(required, ["roots"])
    _ => fail("expected ModernError")
  }
}

///|
test "classify_probe_error: unrecognized failures fall back to legacy" {
  match
    classify_probe_error(@types.TransportError(@types.HttpError(400, "oops"))) {
    FallbackLegacy => ()
    _ => fail("expected FallbackLegacy for unrecognized 400 body")
  }
  match classify_probe_error(@types.TransportError(@types.Timeout)) {
    FallbackLegacy => ()
    _ => fail("expected FallbackLegacy for timeout")
  }
  match classify_probe_error(@types.InternalError("boom")) {
    FallbackLegacy => ()
    _ => fail("expected FallbackLegacy for non-modern protocol error")
  }
}

///|
test "classify_probe_error: HTTP 4xx probe rejections fall back to legacy" {
  // nowledge-mem (2025-11-25 streamable HTTP) answers a non-initialize
  // first message with 422 and a plain-text body; the probe must read that
  // as "legacy-era server", not a fatal failure.
  match
    classify_probe_error(
      @types.TransportError(
        @types.HttpError(422, "Unexpected message, expect initialize request"),
      ),
    ) {
    FallbackLegacy => ()
    _ => fail("expected FallbackLegacy for 422 probe rejection")
  }
  match
    classify_probe_error(
      @types.TransportError(@types.HttpError(404, "no probe here")),
    ) {
    FallbackLegacy => ()
    _ => fail("expected FallbackLegacy for 404 probe rejection")
  }
  // A 4xx body that carries a modern JSON-RPC error still surfaces it.
  let body = "{\"error\":{\"code\":-32021,\"message\":\"need caps\",\"data\":{\"requiredCapabilities\":[\"roots\"]}}}"
  match
    classify_probe_error(@types.TransportError(@types.HttpError(422, body))) {
    ModernError(@types.MissingRequiredClientCapability(_, ..)) => ()
    _ => fail("expected ModernError for 422 carrying a modern error")
  }
  // 5xx is a broken server, not an era signal.
  match
    classify_probe_error(@types.TransportError(@types.HttpError(500, "boom"))) {
    Fatal(_) => ()
    _ => fail("expected Fatal for 5xx probe failure")
  }
}

///|
test "classify_probe_error: transport failures are fatal" {
  match classify_probe_error(@types.TransportError(@types.ConnectionClosed)) {
    Fatal(_) => ()
    _ => fail("expected Fatal")
  }
}

///|
test "build_legacy_meta omits modern keys" {
  @debug.assert_eq(build_legacy_meta(), Json::object({}))
  @debug.assert_eq(
    build_legacy_meta(progress_token="tok"),
    Json::object({ "progressToken": "tok" }),
  )
}

///|
test "apply_legacy_meta_to_request strips empty _meta" {
  let req = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\"}}}"
  let rewritten = apply_legacy_meta_to_request(req, build_legacy_meta())
  let json = @json.parse(rewritten) catch { _ => Json::null() }
  match json {
    Object(obj) =>
      match obj.get("params") {
        Some(Object(params)) => @debug.assert_eq(params.get("_meta"), None)
        _ => fail("expected params object")
      }
    _ => fail("expected request object")
  }
}

///|
test "apply_legacy_meta_to_request replaces _meta when non-empty" {
  let req = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"t\",\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\"}}}"
  let meta = build_legacy_meta(progress_token="p1")
  let rewritten = apply_legacy_meta_to_request(req, meta)
  let json = @json.parse(rewritten) catch { _ => Json::null() }
  match json {
    Object(obj) =>
      match obj.get("params") {
        Some(Object(params)) =>
          @debug.assert_eq(
            params.get("_meta"),
            Some(Json::object({ "progressToken": "p1" })),
          )
        _ => fail("expected params object")
      }
    _ => fail("expected request object")
  }
}
