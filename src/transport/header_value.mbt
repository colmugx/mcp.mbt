///|
/// Encode raw bytes to a standard Base64 string (with padding).
pub fn encode_base64(bytes : Bytes) -> String {
  @base64.std_encode2str(FixedArray::makei(bytes.length(), fn(i) { bytes[i] }))
}

///|
/// Decode a standard Base64 string back to raw bytes. Returns `None` on
/// invalid input (fail-closed).
pub fn decode_base64(s : String) -> Bytes? {
  let decoded = @base64.std_decode2bytes(s) catch { _ => return None }
  Some(decoded)
}

///|
/// Encode a string as a Base64 sentinel value: `=?base64?<b64>?=`.
/// The input is first encoded as UTF-8 bytes.
pub fn encode_base64_sentinel(value : String) -> String {
  "=?base64?" + encode_base64(@utf8.encode(value)) + "?="
}

///|
/// Decode a Base64 sentinel value. Returns `None` if the value is not in
/// sentinel form or if decoding fails (fail-closed).
pub fn decode_base64_sentinel(value : String) -> String? {
  let prefix = "=?base64?"
  let suffix = "?="
  if value.has_prefix(prefix) &&
    value.has_suffix(suffix) &&
    value.length() > prefix.length() + suffix.length() {
    let encoded = value[prefix.length():value.length() - suffix.length()]
    match decode_base64(encoded.to_owned()) {
      Some(bytes) => Some(@utf8.decode(bytes[:])) catch { _ => None }
      None => None
    }
  } else {
    None
  }
}

///|
/// Returns `true` if the value matches the Base64 sentinel pattern.
pub fn looks_like_sentinel(value : String) -> Bool {
  value.has_prefix("=?base64?") && value.has_suffix("?=")
}

///|
/// Returns `true` if `value` can be transmitted as a plain HTTP header value:
/// every character is visible ASCII (`0x21`–`0x7E`), space (`0x20`), or tab
/// (`0x09`); it has no leading/trailing whitespace; and it does not match the
/// sentinel pattern (to avoid ambiguity).
pub fn is_header_safe(value : String) -> Bool {
  if value.is_empty() {
    return true
  }
  match value.get_char(0) {
    Some(' ') | Some('\t') => return false
    _ => ()
  }
  match value.get_char(value.length() - 1) {
    Some(' ') | Some('\t') => return false
    _ => ()
  }
  for c in value {
    let cp = c.to_int()
    if cp != 0x20 && cp != 0x09 && (cp < 0x21 || cp > 0x7E) {
      return false
    }
  }
  !looks_like_sentinel(value)
}

///|
/// Encode a header value according to the spec: plain when safe, otherwise
/// Base64-sentinel encoded.
pub fn encode_header_value(value : String) -> String {
  if is_header_safe(value) {
    value
  } else {
    encode_base64_sentinel(value)
  }
}

///|
/// Returns `true` if `value` contains only characters permitted in a non-
/// sentinel HTTP header value: visible ASCII (`0x21`–`0x7E`), space (`0x20`),
/// or tab (`0x09`). CR and LF are implicitly rejected because they are not in
/// the allowed range.
pub fn is_valid_header_characters(value : String) -> Bool {
  for c in value {
    let cp = c.to_int()
    if cp != 0x20 && cp != 0x09 && (cp < 0x21 || cp > 0x7E) {
      return false
    }
  }
  true
}
