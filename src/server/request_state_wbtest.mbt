///| requestState AEAD codec tests (white-box)
///
/// These exercise the seal/open round-trip and the spec's integrity/replay
/// controls: tamper detection, expiry, principal binding, and params binding.
/// A fixed AES key and fixed wall-clock `now` are used for determinism; the
/// production constructor reads OS entropy via @getrandom and the caller
/// supplies the real clock.

///|
fn fixed_key() -> Bytes {
  // 32 bytes of a recognizable pattern (not for production use).
  Bytes::make(32, b'\x42')
}

///|
/// Fixed "current time" for tests (unix seconds). Expiry values are
/// expressed relative to this so tests are clock-independent.
let test_now : Int = 1_700_000_000

///|
fn future_expiry() -> Int {
  test_now + 3600
}

///|
fn past_expiry() -> Int {
  test_now - 3600
}

///|
test "requestState: seal/open round-trip returns the payload" {
  let codec = AesGcmStateCodec::with_key(fixed_key())
  let payload : RequestStatePayload = {
    principal: Some("alice"),
    expires_at: future_expiry(),
    request_method: "tools/call",
    params_digest: params_digest(
      Json::object({ "name": Json::string("get_weather") }),
    ),
    state: Json::object({ "step": Json::number(1.0) }),
  }
  let blob = codec.seal(payload, now=test_now)
  let ctx : RequestStateContext = {
    principal: Some("alice"),
    request_method: "tools/call",
    params: Json::object({ "name": Json::string("get_weather") }),
  }
  match codec.open(blob, ctx, now=test_now) {
    Some(p) => {
      assert_eq(p.request_method, "tools/call")
      match p.principal {
        Some(pr) => assert_eq(pr, "alice")
        None => panic()
      }
    }
    None => panic()
  }
}

///|
test "requestState: tampered ciphertext is rejected" {
  let codec = AesGcmStateCodec::with_key(fixed_key())
  let payload : RequestStatePayload = {
    principal: None,
    expires_at: future_expiry(),
    request_method: "tools/call",
    params_digest: "",
    state: Json::object({}),
  }
  let blob = codec.seal(payload, now=test_now)
  // Append junk — must fail to open (base64 damage or tag mismatch).
  let tampered = blob + "X"
  let ctx : RequestStateContext = {
    principal: None,
    request_method: "tools/call",
    params: Json::object({}),
  }
  match codec.open(tampered, ctx, now=test_now) {
    Some(_) => panic()
    None => ()
  }
}

///|
test "requestState: expired blob is rejected" {
  let codec = AesGcmStateCodec::with_key(fixed_key())
  let payload : RequestStatePayload = {
    principal: None,
    expires_at: past_expiry(),
    request_method: "tools/call",
    params_digest: params_digest(Json::object({})),
    state: Json::object({}),
  }
  let blob = codec.seal(payload, now=test_now)
  let ctx : RequestStateContext = {
    principal: None,
    request_method: "tools/call",
    params: Json::object({}),
  }
  match codec.open(blob, ctx, now=test_now) {
    Some(_) => panic()
    None => ()
  }
}

///|
test "requestState: principal mismatch is rejected" {
  let codec = AesGcmStateCodec::with_key(fixed_key())
  let payload : RequestStatePayload = {
    principal: Some("alice"),
    expires_at: future_expiry(),
    request_method: "tools/call",
    params_digest: params_digest(Json::object({})),
    state: Json::object({}),
  }
  let blob = codec.seal(payload, now=test_now)
  // Different principal on retry.
  let ctx : RequestStateContext = {
    principal: Some("bob"),
    request_method: "tools/call",
    params: Json::object({}),
  }
  match codec.open(blob, ctx, now=test_now) {
    Some(_) => panic()
    None => ()
  }
}

///|
test "requestState: params mismatch is rejected" {
  let codec = AesGcmStateCodec::with_key(fixed_key())
  let original_params = Json::object({ "name": Json::string("get_weather") })
  let payload : RequestStatePayload = {
    principal: None,
    expires_at: future_expiry(),
    request_method: "tools/call",
    params_digest: params_digest(original_params),
    state: Json::object({}),
  }
  let blob = codec.seal(payload, now=test_now)
  // Retry with different params.
  let ctx : RequestStateContext = {
    principal: None,
    request_method: "tools/call",
    params: Json::object({ "name": Json::string("get_time") }),
  }
  match codec.open(blob, ctx, now=test_now) {
    Some(_) => panic()
    None => ()
  }
}

///|
test "requestState: anonymous principal round-trips" {
  let codec = AesGcmStateCodec::with_key(fixed_key())
  let payload : RequestStatePayload = {
    principal: None,
    expires_at: future_expiry(),
    request_method: "prompts/get",
    params_digest: params_digest(Json::object({})),
    state: Json::string("continuation"),
  }
  let blob = codec.seal(payload, now=test_now)
  let ctx : RequestStateContext = {
    principal: None,
    request_method: "prompts/get",
    params: Json::object({}),
  }
  match codec.open(blob, ctx, now=test_now) {
    Some(p) =>
      match p.state {
        String(s) => assert_eq(s, "continuation")
        _ => panic()
      }
    None => panic()
  }
}
