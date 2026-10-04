///|
/// Property-based tests for the header-value codec. Random inputs come from
/// `@qc`; a failure raises with the shrunk counterexample.

///|
test "prop: encode_header_value roundtrips through sentinel decode" {
  @qc.check((s : String) => {
    let encoded = @transport.encode_header_value(s)
    if @transport.is_header_safe(s) {
      encoded == s
    } else {
      @transport.decode_base64_sentinel(encoded) == Some(s)
    }
  })
}

///|
test "prop: base64 codec is lossless over UTF-8 bytes" {
  @qc.check((s : String) => {
    let bytes = @utf8.encode(s)
    match @transport.decode_base64(@transport.encode_base64(bytes)) {
      Some(out) => out == bytes
      None => false
    }
  })
}

///|
test "prop: encoded header values are always transmittable" {
  // Whatever the input, the encoder's output must be usable as a header
  // value: legal charset and no leading/trailing whitespace.
  @qc.check((s : String) => {
    let enc = @transport.encode_header_value(s)
    @transport.is_valid_header_characters(enc) &&
    !(enc.has_prefix(" ") ||
    enc.has_suffix(" ") ||
    enc.has_prefix("\t") ||
    enc.has_suffix("\t"))
  })
}
