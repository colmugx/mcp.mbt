// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// Opaque compiled pattern. No external regexp type leaks through this API.
pub struct CompiledPattern {
  priv expression : @regexp.Regexp
  priv assertions : Array[(Bool, @regexp.Regexp)]
  priv anchored : Bool
}

///|
pub(all) enum PatternSupport {
  Supported(CompiledPattern)
  Unsupported(reason~ : String)
}

///|
pub(all) suberror PatternError {
  NotSupported(String)
} derive(Debug)

///|
pub extend PatternError with @debug.Debug::{to_repr}

///|
const ECMA_WS : String = " \\t\\n\\v\\f\\r\\u{00A0}\\u{1680}\\u{2000}-\\u{200A}\\u{2028}\\u{2029}\\u{202F}\\u{205F}\\u{3000}\\u{FEFF}"

///|
fn char_at(source : String, index : Int) -> Char {
  source.get_char(index).unwrap_or_else(() => source[index].unsafe_to_char())
}

///|
fn char_width(c : Char) -> Int {
  if c.to_int() > 65535 {
    2
  } else {
    1
  }
}

///|
fn shorthand(c : Char, in_class : Bool) -> String? raise PatternError {
  let content = match c {
    'd' => "0-9"
    'w' => "A-Za-z0-9_"
    's' => ECMA_WS
    'D' | 'W' | 'S' => {
      if in_class {
        raise NotSupported("negated shorthand inside a class is not supported")
      }
      match c {
        'D' => return Some("[^0-9]")
        'W' => return Some("[^A-Za-z0-9_]")
        _ => return Some("[^\{ECMA_WS}]")
      }
    }
    _ => return None
  }
  Some(if in_class { content } else { "[" + content + "]" })
}

///|
fn translate(pattern : String) -> String raise PatternError {
  let output = StringBuilder()
  let mut index = 0
  let mut in_class = false
  while index < pattern.length() {
    let c = char_at(pattern, index)
    if c == '\\' && index + 1 < pattern.length() {
      let next = char_at(pattern, index + 1)
      if in_class &&
        (next == 'd' || next == 'w' || next == 's') &&
        (
          (index > 0 && char_at(pattern, index - 1) == '-') ||
          (index + 2 < pattern.length() && char_at(pattern, index + 2) == '-')
        ) {
        raise NotSupported(
          "shorthand classes used as range endpoints are not supported",
        )
      }
      match shorthand(next, in_class) {
        Some(replacement) => output.write_string(replacement)
        None => {
          output.write_char('\\')
          output.write_char(next)
        }
      }
      index += 1 + char_width(next)
      continue
    }
    if c == '[' && !in_class {
      in_class = true
    } else if c == ']' && in_class {
      in_class = false
    }
    if !in_class && c == '(' && pattern[index:].has_prefix("(?") {
      if pattern[index:].has_prefix("(?=") || pattern[index:].has_prefix("(?!") {
        raise NotSupported("only a leading lookahead chain is supported")
      }
      if pattern[index:].has_prefix("(?<=") ||
        pattern[index:].has_prefix("(?<!") {
        raise NotSupported("lookbehind is not supported")
      }
      if !pattern[index:].has_prefix("(?:") &&
        !pattern[index:].has_prefix("(?<") {
        raise NotSupported(
          "inline regexp flags are outside the supported profile",
        )
      }
    }
    if !in_class && c == '.' {
      output.write_string("[^\\n\\r\\u{2028}\\u{2029}]")
    } else {
      output.write_char(c)
    }
    index += char_width(c)
  }
  output.to_string()
}

///|
// Parse one assertion, retaining balanced noncapturing groups. Captures across
// assertions would change numbering/backreference semantics, so refuse them.
fn assertion_end(pattern : String, start : Int) -> Int raise PatternError {
  let mut index = start + 3
  let mut nesting = 1
  let mut in_class = false
  while index < pattern.length() {
    let c = char_at(pattern, index)
    if c == '\\' && index + 1 < pattern.length() {
      index += 1 + char_width(char_at(pattern, index + 1))
      continue
    }
    if c == '[' && !in_class {
      in_class = true
    } else if c == ']' && in_class {
      in_class = false
    }
    if !in_class {
      if c == '(' {
        if !pattern[index:].has_prefix("(?:") {
          raise NotSupported(
            "captures and nested lookarounds inside assertions are not supported",
          )
        }
        nesting += 1
      } else if c == ')' {
        nesting -= 1
        if nesting == 0 {
          return index
        }
      }
    }
    index += char_width(c)
  }
  raise NotSupported("unterminated lookahead assertion")
}

///|
fn has_top_alternative(pattern : String) -> Bool {
  let mut nesting = 0
  let mut in_class = false
  let mut index = 0
  while index < pattern.length() {
    let c = char_at(pattern, index)
    if c == '\\' && index + 1 < pattern.length() {
      index += 1 + char_width(char_at(pattern, index + 1))
      continue
    }
    if c == '[' && !in_class {
      in_class = true
    } else if c == ']' && in_class {
      in_class = false
    }
    if !in_class {
      if c == '(' {
        nesting += 1
      } else if c == ')' {
        nesting -= 1
      } else if c == '|' && nesting == 0 {
        return true
      }
    }
    index += char_width(c)
  }
  false
}

///|
/// Unanchored search semantics. Supports ordinary regexp.mbt patterns with
/// ECMA digit/word/whitespace rewrites and a precise leading lookahead chain.
/// Other lookarounds and ambiguous rewrites are explicit unsupported errors.
pub fn compile_pattern(pattern : String) -> PatternSupport {
  try {
    let anchored = pattern.has_prefix("^")
    let mut offset = if anchored { 1 } else { 0 }
    let assertions : Array[(Bool, @regexp.Regexp)] = []
    while pattern[offset:].has_prefix("(?=") ||
          pattern[offset:].has_prefix("(?!") {
      if !anchored {
        raise NotSupported(
          "leading lookahead chains must be anchored with ^ in this profile",
        )
      }
      let positive = pattern[offset:].has_prefix("(?=")
      let end = assertion_end(pattern, offset)
      let body = pattern[offset + 3:end].to_owned()
      assertions.push(
        (positive, @regexp.compile("^(?:" + translate(body) + ")")),
      )
      offset = end + 1
    }
    let expression = if assertions.is_empty() {
      @regexp.compile(translate(pattern))
    } else {
      let tail = pattern[offset:].to_owned()
      if has_top_alternative(tail) {
        raise NotSupported(
          "top-level alternatives after a lookahead chain are not supported",
        )
      }
      @regexp.compile("^(?:" + translate(tail) + ")")
    }
    Supported({ expression, assertions, anchored, })
  } catch {
    NotSupported(reason) => Unsupported(reason~)
    _ => Unsupported(reason="pattern rejected by the regexp engine")
  }
}

///|
/// Unsupported patterns cannot silently turn into a false validation result.
pub fn pattern_matches(
  support : PatternSupport,
  text : String,
) -> Bool raise PatternError {
  match support {
    Unsupported(reason~) => raise NotSupported(reason)
    Supported(compiled) => {
      if !compiled.assertions.is_empty() && !compiled.anchored {
        raise NotSupported("invalid compiled assertion origin")
      }
      for entry in compiled.assertions {
        let (positive, assertion) = entry
        if assertion.execute(text).matched() != positive {
          return false
        }
      }
      compiled.expression.execute(text).matched()
    }
  }
}
