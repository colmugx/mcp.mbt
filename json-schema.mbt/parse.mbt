///|
pub(all) suberror ParseError {
  InvalidJson(position~ : Int, reason~ : String)
  DepthLimit(Int)
} derive(Debug)

///|
pub extend ParseError with @debug.Debug::{to_repr}

///|
priv struct JsonParser {
  source : String
  mut offset : Int
  limit : Int
}

///|
/// Parse JSON while retaining every numeric literal in Json::Number's repr.
/// Duplicate object keys use the last value. Offsets are UTF-16 code units.
pub fn parse(
  source : StringView,
  max_nesting_depth? : Int = 128,
) -> Json raise ParseError {
  if max_nesting_depth < 1 {
    raise DepthLimit(max_nesting_depth)
  }
  let parser = {
    source: source.to_owned(),
    offset: 0,
    limit: max_nesting_depth,
  }
  let value = parser.value(0)
  parser.whitespace()
  if parser.offset != parser.source.length() {
    parser.invalid("unexpected trailing input")
  }
  value
}

///|
fn JsonParser::invalid(
  self : JsonParser,
  reason : String,
) -> Unit raise ParseError {
  raise InvalidJson(position=self.offset, reason~)
}

///|
fn JsonParser::peek(self : JsonParser) -> Char? {
  self.source.get_char(self.offset)
}

///|
fn JsonParser::whitespace(self : JsonParser) -> Unit {
  while self.offset < self.source.length() {
    match self.peek() {
      Some(' ' | '\t' | '\r' | '\n') => self.offset += 1
      _ => break
    }
  }
}

///|
fn JsonParser::consume(self : JsonParser, expected : Char) -> Bool {
  if self.peek() == Some(expected) {
    self.offset += 1
    true
  } else {
    false
  }
}

///|
fn JsonParser::expect(
  self : JsonParser,
  expected : Char,
) -> Unit raise ParseError {
  self.whitespace()
  if !self.consume(expected) {
    self.invalid("expected '" + expected.to_string() + "'")
  }
}

///|
fn JsonParser::string(self : JsonParser) -> String raise ParseError {
  let start = self.offset
  if !self.consume('"') {
    self.invalid("expected a string")
  }
  let mut escaped = false
  while self.offset < self.source.length() {
    // Scan code units: slicing at a quote remains safe across surrogate pairs.
    let unit = self.source[self.offset]
    self.offset += 1
    if escaped {
      escaped = false
      continue
    }
    if unit == 92 {
      escaped = true
      continue
    }
    if unit == 34 {
      let token = self.source[start:self.offset]
      let decoded = @json.parse(token) catch {
        _ => {
          self.invalid("invalid string escape")
          Json::null()
        }
      }
      match decoded {
        String(text) => return text
        _ => self.invalid("expected a string token")
      }
    }
    if unit < 32 {
      self.invalid("unescaped control character")
    }
  }
  self.invalid("unterminated string")
  ""
}

///|
fn JsonParser::digits(self : JsonParser) -> Int {
  let start = self.offset
  while self.peek() is Some(c) && c >= '0' && c <= '9' {
    self.offset += 1
  }
  self.offset - start
}

///|
fn JsonParser::number(self : JsonParser) -> Json raise ParseError {
  let start = self.offset
  ignore(self.consume('-'))
  if self.consume('0') {
    if self.peek() is Some(c) && c >= '0' && c <= '9' {
      self.invalid("leading zero in number")
    }
  } else if self.digits() == 0 {
    self.invalid("number requires integer digits")
  }
  if self.consume('.') && self.digits() == 0 {
    self.invalid("number requires fractional digits")
  }
  if self.consume('e') || self.consume('E') {
    if !self.consume('+') {
      ignore(self.consume('-'))
    }
    if self.digits() == 0 {
      self.invalid("number requires exponent digits")
    }
  }
  let token = self.source[start:self.offset].to_owned()
  if ExactNumber::from_literal(token) is None {
    self.invalid("number exceeds supported decimal representation")
  }
  let binary = match literal_double(token) {
    Some(number) => number
    None => {
      self.invalid("invalid number")
      0.0
    }
  }
  Json::number(binary, repr=token)
}

///|
fn JsonParser::literal(
  self : JsonParser,
  spelling : String,
  value : Json,
) -> Json raise ParseError {
  if !self.source[self.offset:].has_prefix(spelling) {
    self.invalid("invalid literal")
  }
  self.offset += spelling.length()
  value
}

///|
fn JsonParser::value(self : JsonParser, depth : Int) -> Json raise ParseError {
  if depth > self.limit {
    raise DepthLimit(self.limit)
  }
  self.whitespace()
  match self.peek() {
    Some('"') => Json::string(self.string())
    Some('t') => self.literal("true", Json::boolean(true))
    Some('f') => self.literal("false", Json::boolean(false))
    Some('n') => self.literal("null", Json::null())
    Some('-' | '0'..='9') => self.number()
    Some('[') => {
      self.offset += 1
      let values : Array[Json] = []
      self.whitespace()
      if self.consume(']') {
        return Json::array(values)
      }
      while true {
        values.push(self.value(depth + 1))
        self.whitespace()
        if self.consume(']') {
          break
        }
        self.expect(',')
      }
      Json::array(values)
    }
    Some('{') => {
      self.offset += 1
      let fields : Map[String, Json] = Map([])
      self.whitespace()
      if self.consume('}') {
        return Json::object(fields)
      }
      while true {
        self.whitespace()
        let key = self.string()
        self.expect(':')
        fields.set(key, self.value(depth + 1))
        self.whitespace()
        if self.consume('}') {
          break
        }
        self.expect(',')
      }
      Json::object(fields)
    }
    _ => {
      self.invalid("expected a JSON value")
      Json::null()
    }
  }
}
