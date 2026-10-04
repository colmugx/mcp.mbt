///| Pure-logic Origin header policy for DNS rebinding prevention
/// (spec basic/transports/streamable-http#security-endpoint: servers must
/// validate Origin on all incoming connections). All-target like
/// jsonrpc_logic.mbt: the policy itself has no I/O, so js (and wasm-gc) keep
/// and test it even though the server transport is gated.

///|
/// Strip a leading `http://` or `https://` scheme. Any other shape — missing
/// scheme, other schemes such as `file:`/`ftp:`, or the bare `null` some
/// sandboxed browsers send — is malformed and fails closed (`None`).
fn strip_origin_scheme(origin : String) -> String? {
  if origin is [.. "https://", .. rest] {
    Some(rest.to_owned())
  } else if origin is [.. "http://", .. rest] {
    Some(rest.to_owned())
  } else {
    None
  }
}

///|
/// Extract the host of an Origin value shaped `scheme://host[:port]`,
/// keeping the brackets on IPv6 literals (`[::1]`). Fail-closed: `None` on a
/// path/query/fragment suffix (Origin carries only an authority), an
/// unterminated IPv6 literal, an empty host, or a missing/non-numeric port.
fn origin_host(origin : String) -> String? {
  let authority = match strip_origin_scheme(origin) {
    Some(a) => a
    None => return None
  }
  let host = StringBuilder()
  let mut in_brackets = false
  let mut in_port = false
  let mut port_digits = 0
  for c in authority {
    if in_port {
      match c {
        '0'..='9' => port_digits += 1
        _ => return None
      }
    } else {
      match c {
        '/' | '?' | '#' => return None
        '[' =>
          if in_brackets {
            return None
          } else {
            in_brackets = true
            host.write_char('[')
          }
        ']' =>
          if in_brackets {
            in_brackets = false
            host.write_char(']')
          } else {
            return None
          }
        ':' =>
          if in_brackets {
            // Colon inside an IPv6 literal is part of the address.
            host.write_char(':')
          } else {
            in_port = true
          }
        _ => host.write_char(c)
      }
    }
  }
  if in_brackets || (in_port && port_digits == 0) || host.to_string() is "" {
    None
  } else {
    Some(host.to_string())
  }
}

///|
/// Decide whether a request `Origin` value may reach the MCP endpoint.
///
/// - `allowed_origins = Some(list)` (auth configured with an allowlist): the
///   value must match one entry exactly; the allowlist replaces, not extends,
///   the default policy.
/// - `allowed_origins = None` (no auth, or auth without an allowlist): the
///   default policy admits only loopback origins — `http`/`https` with host
///   `127.0.0.1`, `localhost`, or `[::1]` on any port — so a page served
///   from a rebound public DNS name cannot pass. Malformed values and every
///   other host fail closed.
///
/// Requests carrying no Origin header are non-browser clients; the caller
/// allows them without consulting this function.
pub fn origin_allowed(
  origin : String,
  allowed_origins : Array[String]?,
) -> Bool {
  match allowed_origins {
    Some(list) => list.exists(fn(o) { o == origin })
    None =>
      match origin_host(origin) {
        Some(host) => {
          let h = host.to_lower()
          h == "127.0.0.1" || h == "localhost" || h == "[::1]"
        }
        None => false
      }
  }
}
