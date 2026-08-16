///|
/// Backend selected after era probing. Modern clients speak the stateless
/// 2026-07-28 protocol; Legacy clients wrap the 2025-11-25 session client.
pub enum ClientBackend {
  Modern
  Legacy(@legacy.LegacyClient)
}

///|
/// Outcome of classifying a probe failure.
priv enum ProbeVerdict {
  /// The server returned a recognized modern JSON-RPC error
  /// (-32020/-32021/-32022). The carried error should be surfaced to the user.
  ModernError(@types.MCPError)
  /// The failure is not modern; fall back to a legacy client if possible.
  FallbackLegacy
  /// A transport-level failure that should not trigger legacy fallback.
  Fatal
}

///|
/// Parse a JSON-RPC error body and return a strongly-typed MCPError when the
/// error code is one of the modern era-probe codes:
///   - -32020 HeaderMismatch
///   - -32021 MissingRequiredClientCapability
///   - -32022 UnsupportedProtocolVersion
fn parse_jsonrpc_error(body : String) -> @types.MCPError? {
  let json = @json.parse(body) catch { _ => return None }
  if json is Object(obj) {
    match obj.get("error") {
      Some(Object(err_obj)) => {
        let code = match err_obj.get("code") {
          Some(Number(n, ..)) => n.to_int()
          _ => return None
        }
        let message = match err_obj.get("message") {
          Some(String(s)) => s
          _ => "Unknown error"
        }
        let data = err_obj.get("data")
        match code {
          -32020 => Some(@types.HeaderMismatch(message))
          -32021 => {
            let required = match data {
              Some(Object(d)) =>
                match d.get("requiredCapabilities") {
                  Some(Array(arr)) =>
                    arr.filter_map(fn(j) {
                      match j {
                        String(s) => Some(s)
                        _ => None
                      }
                    })
                  _ => []
                }
              _ => []
            }
            Some(@types.MissingRequiredClientCapability(message, required~))
          }
          -32022 => {
            let (supported, requested) = match data {
              Some(Object(d)) => {
                let supported = match d.get("supported") {
                  Some(Array(arr)) =>
                    arr.filter_map(fn(j) {
                      match j {
                        String(s) => Some(s)
                        _ => None
                      }
                    })
                  _ => []
                }
                let requested = match d.get("requested") {
                  Some(String(s)) => s
                  _ => @types.ProtocolVersion
                }
                (supported, requested)
              }
              _ => ([], @types.ProtocolVersion)
            }
            Some(
              @types.UnsupportedProtocolVersion(message, supported~, requested~),
            )
          }
          _ => None
        }
      }
      _ => None
    }
  } else {
    None
  }
}

///|
/// Classify a probe failure into one of three verdicts.
///
/// * Modern JSON-RPC errors (directly or carried in an HTTP 400 body) mean the
///   server is modern but rejected the probe; surface the error.
/// * HTTP 400 bodies that do not contain a recognized modern error, and direct
///   modern-era errors that are not transport failures, trigger legacy fallback.
/// * Non-HTTP transport failures (connection refused, invalid state, etc.) are
///   fatal and should propagate without fallback.
fn classify_probe_error(err : @types.MCPError) -> ProbeVerdict {
  match err {
    @types.HeaderMismatch(_)
    | @types.MissingRequiredClientCapability(_, ..)
    | @types.UnsupportedProtocolVersion(_, ..) => ModernError(err)
    @types.TransportError(te) =>
      match te {
        @types.HttpError(400, body) =>
          match parse_jsonrpc_error(body) {
            Some(modern_err) => ModernError(modern_err)
            None => FallbackLegacy
          }
        @types.Timeout => FallbackLegacy
        _ => Fatal
      }
    _ => FallbackLegacy
  }
}

///|
/// Build the `_meta` object used for legacy requests. It omits all
/// `io.modelcontextprotocol/*` keys and only carries a progress token when one
/// is supplied.
fn build_legacy_meta(progress_token? : String = "") -> Json {
  let meta : Map[String, Json] = Default::default()
  if progress_token != "" {
    meta.set("progressToken", Json::string(progress_token))
  }
  Json::object(meta)
}

///|
/// Rewrite a modern request so its `params._meta` is suitable for a legacy
/// server. If `meta` is empty, `_meta` is removed entirely; otherwise it is
/// replaced with the provided legacy meta.
fn apply_legacy_meta_to_request(request : String, meta : Json) -> String {
  let json = @json.parse(request) catch { _ => return request }
  if json is Object(obj) {
    match obj.get("params") {
      Some(Object(params)) => {
        let meta_obj = match meta {
          Object(m) => Some(m)
          _ => None
        }
        match meta_obj {
          Some(m) =>
            if m.is_empty() {
              params.remove("_meta")
            } else {
              params.set("_meta", meta)
            }
          None => params.remove("_meta")
        }
        obj.set("params", Json::object(params))
      }
      _ => ()
    }
    json.stringify()
  } else {
    request
  }
}

///|
/// Send a raw `server/discover` probe over the given transport and parse the
/// response. Returns the server capabilities on success, or a failure that can
/// be classified by `classify_probe_error`.
async fn send_discover_probe(
  transport : @transport.AnyTransport,
  meta : Json,
) -> Result[@types.ServerCapabilities, @types.MCPError] {
  let id = 1
  let request = build_discover_request(id, meta)
  transport.send(request) catch {
    e => return Err(@types.TransportError(e))
  }
  let response = transport.receive() catch {
    e => return Err(@types.TransportError(e))
  }
  let response_str = match response {
    Some(s) => s
    None => return Err(@types.TransportError(@types.ConnectionClosed))
  }
  // Recognize modern JSON-RPC errors before the generic parser loses the code.
  match parse_jsonrpc_error(response_str) {
    Some(modern_err) => return Err(modern_err)
    None => ()
  }
  match parse_jsonrpc_response(response_str) {
    Err(e) => Err(e)
    Ok(result_json) => {
      let caps = parse_discover_capabilities(result_json)
      Ok(caps)
    }
  }
}
