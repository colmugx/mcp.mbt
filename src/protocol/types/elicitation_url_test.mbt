///|
test "elicitation URL syntax is validated without imposing HTTPS or fetching" {
  for
    url in [
      "https://example.org/path?q=%20#part", "http://localhost:8080/form", "https://[::1]:443/form",
      "https://[::ffff:127.0.0.1]/form", "custom:interaction", "https://例子.测试/确认",
      "http://localhost:/form",
    ] {
    ignore(
      @types.ElicitationRequest::from_json({
        "mode": "url",
        "message": "Continue",
        "url": Json::string(url),
      }),
    )
  }
  for
    url in [
      "", "/relative", "example.org", "https:", "https:/missing-host", "https://",
      "https://host:bad", "https://[::1", "https://[gggg]", "https://host:65536",
      "https://host/\n", "https://host/%GG", "https://[::127.0.0.1:127.0.0.1]/form",
    ] {
    try
      @types.ElicitationRequest::from_json({
        "mode": "url",
        "message": "Continue",
        "url": Json::string(url),
      })
    catch {
      @types.InvalidParams(_) => ()
      error => raise error
    } noraise {
      _ => fail("invalid URL accepted: " + url)
    }
  }
}
