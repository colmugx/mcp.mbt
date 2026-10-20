///|
fn http_response_status(message : String) -> (Int32, String) {
  match jsonrpc_error_code(message) {
    Some(-32020 | -32021 | -32022) => (400, "Bad Request")
    Some(-32601) => (404, "Not Found")
    _ => (200, "OK")
  }
}
