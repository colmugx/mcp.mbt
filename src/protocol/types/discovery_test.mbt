///|
test "discovery round trip preserves versions cache hints and server metadata" {
  let wire : Json = {
    "supportedVersions": ["2026-07-28", "future"],
    "capabilities": { "completions": {}, "future": {} },
    "instructions": "Use tools to inspect the workspace.",
    "resultType": "complete",
    "ttlMs": 1200,
    "cacheScope": "private",
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {
        "name": "test",
        "version": "1",
        "future": 3,
      },
      "custom": null,
    },
    "future": false,
  }
  let result = @types.DiscoverResult::from_json(wire)
  assert_eq(result.to_json(), wire)
  assert_true(result.metadata.server_info() is Some(_))
  assert_eq(result.metadata.ttl_ms, Some(1200))
}

///|
test "discovery rejects missing or malformed required and cache fields" {
  for
    wire in [
      Json::object({ "capabilities": {} }),
      Json::object({
        "supportedVersions": ["2026-07-28", 1],
        "capabilities": {},
      }),
      Json::object({ "supportedVersions": [], "capabilities": {}, "ttlMs": 1.5 }),
      Json::object({
        "supportedVersions": [],
        "capabilities": {},
        "cacheScope": "shared",
      }),
    ] {
    try @types.DiscoverResult::from_json(wire) catch {
      @types.InvalidParams(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("malformed discovery must be rejected")
    }
  }
}
