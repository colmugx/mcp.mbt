///| requestState AEAD codec (server-only)
///
/// Implements the `requestState` field of MCP 2026-07-28 Multi Round-Trip
/// Requests (MRTR). When a server needs client input to finish a request, it
/// returns an `InputRequiredResult` whose `requestState` is an opaque blob
/// the client echoes back on retry. This module seals that blob with
/// AES-256-GCM (authenticated encryption), so the server can hand state to
/// the client without trusting the client with its contents or integrity.
///
/// Dependencies (server-only, see MIGRATION-0.15.md §Crypto boundary):
/// - `@getrandom` — OS entropy for the AES key (once) and each GCM nonce.
/// - `@mooncry` — AES-256-GCM, SHA-256, Base64.
///
/// The sealed blob is base64url-encoded (RFC 4648 §5, no padding) for
/// transport safety in JSON strings and URL parameters.
///
/// Per spec (basic/patterns/mrtr#server-requirements), the integrity-protected
/// payload carries: the authenticated principal, a short expiry, and a digest
/// of the originating request's salient params. `open` verifies all three.

///|
/// Domain-separation constant mixed into AES-GCM AAD so a `requestState` blob
/// cannot be replayed as any other ciphertext consumed by this server.
let request_state_aad : Bytes = @utf8.encode("mcp-requeststate-v1")

///|
/// The maximum clock skew tolerated when checking `expires_at` (unix seconds).
/// Bounded so a blob expiring "now" is still accepted within this window.
let request_state_clock_skew : Int = 5

///|
/// What the server seals into a `requestState` blob. All fields except `state`
/// are integrity/replay controls; `state` is the server's own opaque
/// continuation data (re-derived on retry, never trusted from the client
/// without verification).
pub(all) struct RequestStatePayload {
  /// Authenticated principal; `None` for anonymous. `open` rejects a blob
  /// presented by a different principal.
  principal : String?
  /// Unix-seconds expiry. `open` rejects `now > expires_at + skew`.
  expires_at : Int
  /// Originating request method (e.g. "tools/call"). Binds the blob to the
  /// retry request method.
  request_method : String
  /// Hex SHA-256 of the canonical JSON of the retry's salient params. Binds
  /// the blob to the retry request body.
  params_digest : String
  /// Server's own continuation state. Opaque to the client; verified on open.
  state : Json
}

///|
/// Context checked by `open`, computed from the incoming retry request.
pub(all) struct RequestStateContext {
  principal : String?
  request_method : String
  /// The retry request params; re-hashed and compared to `params_digest`.
  params : Json
}

///|
/// Seals/opens `requestState` blobs. Implementations MUST be authenticated
/// (AEAD or HMAC) per spec.
///
/// `now` (unix seconds) is passed in by the caller rather than read from a
/// clock inside the codec: it keeps the codec free of a time-package
/// dependency and makes expiry behavior deterministic in tests.
pub trait RequestStateCodec {
  /// Serialize + protect `payload` at wall-clock time `now`. Output is a
  /// transport-safe opaque string.
  fn seal(Self, RequestStatePayload, now~ : Int) -> String

  /// Verify + deserialize at wall-clock time `now`. Returns `None` on any
  /// integrity failure, expiry, principal mismatch, or params mismatch.
  fn open(Self, String, RequestStateContext, now~ : Int) -> RequestStatePayload?
}

///|
/// AES-256-GCM codec. Holds a 32-byte key only — each `seal` draws a fresh
/// 12-byte nonce from the OS CSPRNG (`@getrandom`), so there is no counter
/// state to synchronize across instances and no risk of nonce reuse.
pub struct AesGcmStateCodec {
  key : Bytes // 32 bytes (AES-256)
}

///|
/// Construct a codec with a caller-supplied 32-byte key (e.g. distributed to
/// all instances sharing MRTR state). Aborts if the key is not 32 bytes.
pub fn AesGcmStateCodec::with_key(key : Bytes) -> AesGcmStateCodec {
  if key.length() != 32 {
    abort("AesGcmStateCodec: key must be 32 bytes (AES-256)")
  }
  { key, }
}

///|
/// Construct a codec by reading 32 bytes of OS entropy via `@getrandom`.
/// Server startup only. Aborts if the OS entropy source is unavailable.
pub fn AesGcmStateCodec::AesGcmStateCodec() -> AesGcmStateCodec {
  match @getrandom.getrandom(32) {
    Ok(k) => AesGcmStateCodec::with_key(k)
    Err(e) =>
      abort(
        "AesGcmStateCodec: failed to read OS entropy for requestState key: " + e,
      )
  }
}

///|
impl RequestStateCodec for AesGcmStateCodec with fn seal(
  self,
  payload : RequestStatePayload,
  now~ : Int,
) -> String {
  // `now` is unused at seal time; expiry is carried in the payload by the
  // caller. The parameter exists for interface symmetry with `open`.
  ignore(now)
  let plaintext = @utf8.encode(payload_to_json(payload))
  // Fresh random nonce per seal — no counter, no reuse risk.
  let nonce = match @getrandom.getrandom(12) {
    Ok(n) => n
    Err(e) =>
      abort("AesGcmStateCodec: failed to read OS entropy for nonce: " + e)
  }
  let (ct, tag) = @mooncry.aes_gcm_encrypt(
    plaintext,
    self.key,
    nonce,
    request_state_aad,
  )
  // blob = nonce(12) || ciphertext || tag(16), then base64url.
  base64url_encode(concat_bytes([nonce, ct, tag]))
}

///|
impl RequestStateCodec for AesGcmStateCodec with fn open(
  self,
  blob : String,
  ctx : RequestStateContext,
  now~ : Int,
) -> RequestStatePayload? {
  let raw = base64url_decode(blob)
  // blob = nonce(12) || ciphertext || tag(16); need at least 12+16 bytes.
  if raw.length() < 28 {
    return None
  }
  let ct_len = raw.length() - 28
  let nonce = slice_bytes(raw, 0, 12)
  let ct = slice_bytes(raw, 12, ct_len)
  let tag = slice_bytes(raw, 12 + ct_len, 16)
  let (pt, ok) = @mooncry.aes_gcm_decrypt(
    ct,
    self.key,
    nonce,
    request_state_aad,
    tag,
  )
  if !ok {
    return None
  }
  let payload = match parse_payload_json(@utf8.decode_lossy(pt)) {
    Some(p) => p
    None => return None
  }
  // Replay/integrity controls per spec §mrtr server-requirements.
  if payload.principal != ctx.principal {
    return None
  }
  if payload.request_method != ctx.request_method {
    return None
  }
  let expected_digest = params_digest(ctx.params)
  if payload.params_digest != expected_digest {
    return None
  }
  if now > payload.expires_at + request_state_clock_skew {
    return None
  }
  Some(payload)
}

///|
/// Declare `seal`/`open` as explicit methods on `AesGcmStateCodec` so trait
/// method promotion is not implicitly relied upon (implicit promotion is
/// deprecated).
pub extend AesGcmStateCodec with RequestStateCodec::{seal, open}

///|
/// Concatenate a list of byte slices into a single `Bytes`. Used to assemble
/// the `nonce || ciphertext || tag` blob without per-element mutation.
fn concat_bytes(parts : Array[Bytes]) -> Bytes {
  let arr : Array[Byte] = []
  for p in parts {
    for i in 0..<p.length() {
      arr.push(p[i])
    }
  }
  Bytes::from_array(arr)
}

///|
/// Take `len` bytes starting at `start`. Caller ensures the range is in bounds.
fn slice_bytes(src : Bytes, start : Int, len : Int) -> Bytes {
  let arr : Array[Byte] = Array::make(len, b'\x00')
  for i in 0..<len {
    arr[i] = src[start + i]
  }
  Bytes::from_array(arr)
}

///|
fn base64url_encode(data : Bytes) -> String {
  @base64.url_encode2str(
    FixedArray::makei(data.length(), fn(i) { data[i] }),
    no_padding=true,
  )
}

///|
fn base64url_decode(encoded : String) -> Bytes {
  @base64.url_decode2bytes(encoded, no_padding=true) catch {
    _ => Bytes::from_array([])
  }
}

///|
/// Hex SHA-256 of the canonical JSON encoding of `params`. Binds a
/// `requestState` blob to the retry request's body so it cannot be replayed
/// against a different request.
fn params_digest(params : Json) -> String {
  let canonical = canonical_json(params)
  @mooncry.bytes_to_hex(@mooncry.sha256(@utf8.encode(canonical)))
}

///|
/// Canonical JSON for digest stability: object keys emitted in sorted order,
/// no insignificant whitespace. Non-object values use `stringify()` (their
/// encoding is already canonical). This is a minimal canonicalizer sufficient
/// for params digesting; it does not aim for full JCS compliance.
fn canonical_json(value : Json) -> String {
  match value {
    Object(obj) => {
      let pairs : Array[(String, Json)] = []
      obj.each(fn(k, v) { pairs.push((k, v)) })
      // Selection sort on key (small maps; avoids comparator API churn).
      for i = 0; i < pairs.length(); i = i + 1 {
        for j = i + 1; j < pairs.length(); j = j + 1 {
          if pairs[j].0 < pairs[i].0 {
            let tmp = pairs[i]
            pairs[i] = pairs[j]
            pairs[j] = tmp
          }
        }
      }
      let fields = pairs
        .map(fn(p) { json_string_escape(p.0) + ":" + canonical_json(p.1) })
        .join(",")
      "{" + fields + "}"
    }
    _ => value.stringify()
  }
}

///|
/// JSON-encode a string literal (with surrounding quotes).
fn json_string_escape(s : String) -> String {
  let mut out = "\""
  for c in s {
    match c {
      '"' => out = out + "\\\""
      '\\' => out = out + "\\\\"
      '\n' => out = out + "\\n"
      '\r' => out = out + "\\r"
      '\t' => out = out + "\\t"
      _ => out = out + c.to_string()
    }
  }
  out + "\""
}

///|
/// Serialize a payload to canonical JSON for sealing. Field order is fixed
/// for digest independence.
fn payload_to_json(payload : RequestStatePayload) -> String {
  let principal = match payload.principal {
    Some(p) => json_string_escape(p)
    None => "null"
  }
  let state = payload.state.stringify()
  "{\"principal\":" +
  principal +
  ",\"expires_at\":" +
  payload.expires_at.to_string() +
  ",\"request_method\":" +
  json_string_escape(payload.request_method) +
  ",\"params_digest\":" +
  json_string_escape(payload.params_digest) +
  ",\"state\":" +
  state +
  "}"
}

///|
/// Parse a payload from JSON. Inverse of `payload_to_json`.
fn parse_payload_json(s : String) -> RequestStatePayload? {
  let json = @json.parse(s) catch { _ => return None }
  if !(json is Object(_)) {
    return None
  }
  let principal = get_field(json, "principal")
  let expires_at = match get_number_field(json, "expires_at") {
    Some(n) => n
    None => return None
  }
  let request_method = match get_field(json, "request_method") {
    Some(m) => m
    None => return None
  }
  let params_digest = match get_field(json, "params_digest") {
    Some(d) => d
    None => return None
  }
  let state = if json is Object(obj) {
    match obj.get("state") {
      Some(s) => s
      None => return None
    }
  } else {
    return None
  }
  Some({ principal, expires_at, request_method, params_digest, state })
}

///|
fn get_field(json : Json, key : String) -> String? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(String(s)) => Some(s)
      _ => None
    }
  } else {
    None
  }
}

///|
/// Extract a numeric field as an Int (truncating any fractional part).
fn get_number_field(json : Json, key : String) -> Int? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(Number(n, ..)) => Some(n.to_int())
      _ => None
    }
  } else {
    None
  }
}
