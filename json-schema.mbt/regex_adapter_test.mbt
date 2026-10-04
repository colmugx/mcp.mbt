///|
fn matched(pattern : String, text : String) -> Bool raise {
  @json-schema.pattern_matches(@json-schema.compile_pattern(pattern), text)
}

///|
test "patterns: ASCII shorthand classes and class context" {
  assert_true(matched("^\\d{3}$", "123"))
  assert_false(matched("^\\d{3}$", "١٢٣"))
  assert_false(matched("^\\d{3}$", "x123"))
  assert_true(matched("^[\\dA-F]+$", "1AF"))
  assert_false(matched("^[^\\d]+$", "1AF"))
  assert_true(matched("^[^\\d]+$", "xyz"))
  assert_true(matched("^\\w+$", "a_bC1"))
  assert_false(matched("^\\w+$", "中文"))
  assert_true(matched("^\\D+$", "abc"))
  assert_false(matched("^\\D+$", "abc1"))
}

///|
test "patterns: ECMA whitespace and dot line terminators" {
  for text in [" ", "\t", "\n", "\r", "\u{00A0}", "\u{2028}", "\u{FEFF}"] {
    assert_true(matched("^\\s$", text))
    assert_true(matched("^[\\s]$", text))
    assert_false(matched("^\\S$", text))
  }
  for text in ["\n", "\r", "\u{2028}", "\u{2029}"] {
    assert_false(matched("^.$", text))
  }
  assert_false(matched("^\\s$", "\u{0085}"))
  assert_true(matched("^\\S$", "\u{0085}"))
}

///|
test "patterns: search semantics, captures, backreferences and emoji" {
  assert_true(matched("b{2}", "abbc"))
  assert_false(matched("^bb$", "abbc"))
  assert_true(matched("^(a)\\1$", "aa"))
  assert_false(matched("^(a)\\1$", "ab"))
  assert_true(matched("^(?<year>\\d{4})-\\d{2}$", "2024-03"))
  assert_true(matched("^😀\\d$", "😀1"))
  assert_false(matched("^😀\\d$", "😀x"))
  assert_true(matched("^\\[\\d\\]$", "[1]"))
  assert_true(matched("\\p{Lu}", "aB"))
}

///|
test "patterns: precise leading assertion chain" {
  assert_true(matched("^(?=\\d{3}$)\\d+$", "123"))
  assert_false(matched("^(?=\\d{3}$)\\d+$", "1234"))
  assert_true(matched("^(?=.{3}$)(?!000)\\d+$", "123"))
  assert_false(matched("^(?=.{3}$)(?!000)\\d+$", "000"))
  assert_true(matched("^(?=(?:ab|cd)$)[a-z]+$", "ab"))
  assert_false(matched("^(?=(?:ab|cd)$)[a-z]+$", "ef"))
}

///|
test "patterns: unsupported constructs and malformed patterns never become false" {
  for
    pattern in [
      "[", "a(?=b)", "(?=a)a", "(?<=a)b", "^(?=(a))a", "^(?=a)a|b", "^[\\D]$", "(?i)a",
    ] {
    let support = @json-schema.compile_pattern(pattern)
    assert_true(support is Unsupported(..), msg=pattern)
    let errored = try {
      ignore(@json-schema.pattern_matches(support, "anything"))
      false
    } catch {
      _ => true
    }
    assert_true(errored)
  }
}
