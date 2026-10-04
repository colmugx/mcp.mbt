// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

// Exact numeric semantics for JSON Schema numeric keywords (2020-12 §6.2).
//
// Every predicate here is exact. There is no epsilon: `0.3` IS a multiple of
// `0.1`, and `1.0000000001` is NOT a multiple of `1`, however convenient the
// opposite would be for floating-point arithmetic. This layer deliberately
// avoids tolerance checks and rounded quotients.

///|
/// A number taken from a JSON tree, kept exactly.
///
/// `Repr` numbers carry the literal as written (`"0.3"`, `"1e10"`); `Double`
/// numbers were constructed in code and only the IEEE value remains. The
/// representation stays private: literal validation is exact, while `Double`
/// validation uses the finite double's shortest decimal rendering. Original
/// digits discarded by another parser cannot be recovered.
pub enum ExactNumber {
  Repr(coeff~ : @bigint.BigInt, scale~ : Int)
  Double(Double)
}

///|
/// A Json number node read as exactly as the source allows: parsed trees
/// carry only the double (`@json.parse` does not keep literal text on this
/// toolchain — verified by probe), constructed trees may carry a repr.
pub fn ExactNumber::of_json(v : Json) -> ExactNumber? {
  match v {
    Number(d, repr~) =>
      match repr {
        Some(text) => {
          let exact = ExactNumber::from_literal(text)
          guard exact is Some(_) else { return None }
          let parsed = literal_double(text)
          match parsed {
            Some(binary) => if binary != d || d.is_nan() { None } else { exact }
            None => None
          }
        }
        None => if d.is_inf() || d.is_nan() { None } else { Some(Double(d)) }
      }
    _ => None
  }
}

///|
/// Interpret a Json number node's literal exactly when available.
pub fn ExactNumber::from_double(v : Double) -> ExactNumber {
  Double(v)
}

///|
priv struct Parts {
  coeff : String
  scale : Int
  negative : Bool
}

///|
/// Lex a JSON number literal into (coefficient digits, decimal exponent of
/// the last digit). Accepts exactly the JSON number grammar.
fn parse_parts(text : String) -> Parts? {
  let s = text
  let n = s.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut negative = false
  match s.get_char(0) {
    Some('-') => {
      negative = true
      i = 1
    }
    Some('+') => return None
    _ => ()
  }
  let int_digits = StringBuilder()
  let frac_digits = StringBuilder()
  let mut seen_int = false
  while i < n {
    match s.get_char(i) {
      Some(c) if c >= '0' && c <= '9' => {
        int_digits.write_char(c)
        seen_int = true
        i += 1
      }
      _ => break
    }
  }
  if !seen_int {
    return None
  }
  // JSON leading-zero rule: "0" alone or "0.x" — "01" is invalid
  let ints = int_digits.to_string()
  if ints.length() > 1 && ints.get_char(0) == Some('0') {
    return None
  }
  if i < n && s.get_char(i) == Some('.') {
    i += 1
    let mut seen_frac = false
    while i < n {
      match s.get_char(i) {
        Some(c) if c >= '0' && c <= '9' => {
          frac_digits.write_char(c)
          seen_frac = true
          i += 1
        }
        _ => break
      }
    }
    if !seen_frac {
      return None
    }
  }
  let mut exp : Int64 = 0
  if i < n {
    match s.get_char(i) {
      Some('e') | Some('E') => {
        i += 1
        let mut exp_negative = false
        match s.get_char(i) {
          Some('+') => i += 1
          Some('-') => {
            exp_negative = true
            i += 1
          }
          _ => ()
        }
        let digits = StringBuilder()
        while i < n {
          match s.get_char(i) {
            Some(c) if c >= '0' && c <= '9' => {
              digits.write_char(c)
              i += 1
            }
            _ => break
          }
        }
        if digits.to_string() == "" {
          return None
        }
        let mag = @string.parse_int64(digits.to_string()) catch {
          _ => return None
        }
        exp = if exp_negative { -mag } else { mag }
        if exp > 100000L || exp < -100000L {
          return None
        }
      }
      _ => ()
    }
  }
  if i != n {
    return None
  }
  let fracs = frac_digits.to_string()
  let all_digits = ints + fracs
  let scale64 : Int64 = fracs.length().to_int64() - exp
  if scale64 > 100000L || scale64 < -100000L {
    return None
  }
  Some({ coeff: all_digits, scale: scale64.to_int(), negative, })
}

///|
// The core parser signals binary64 overflow as Failure. A valid decimal
// lexeme remains a JSON number; its repr, not the infinity placeholder, is
// authoritative for every mathematical predicate.
fn literal_double(text : String) -> Double? {
  guard parse_parts(text) is Some(parts) else { return None }
  Some(@string.parse_double(text)) catch {
    _ => {
      let mut leading = 0
      while leading < parts.coeff.length() &&
            parts.coeff.get_char(leading) == Some('0') {
        leading += 1
      }
      if leading == parts.coeff.length() {
        return Some(if parts.negative { -0.0 } else { 0.0 })
      }
      let order = parts.coeff.length() - leading - 1 - parts.scale
      if order < 308 {
        return None
      }
      let infinity = 1.0 / 0.0
      Some(if parts.negative { -infinity } else { infinity })
    }
  }
}

///|
/// Interpret a decimal literal (JSON number grammar) exactly.
pub fn ExactNumber::from_literal(text : String) -> ExactNumber? {
  match parse_parts(text) {
    Some(parts) => {
      let signed = if parts.negative && parts.coeff != "0" {
        "-" + parts.coeff
      } else {
        parts.coeff
      }
      match @bigint.BigInt::from_string(signed) {
        coeff => Some(Repr(coeff~, scale=parts.scale))
      }
    }
    None => None
  }
}

///|
pub(all) suberror NumericError {
  InvalidNumber
} derive(Debug)

///|
pub extend NumericError with @debug.Debug::{to_repr}

///|
fn ExactNumber::parts(
  self : ExactNumber,
) -> (@bigint.BigInt, Int) raise NumericError {
  match self {
    Repr(coeff~, scale~) => {
      if scale < -100000 || scale > 100000 {
        raise InvalidNumber
      }
      (coeff, scale)
    }
    Double(value) => {
      if value.is_inf() || value.is_nan() {
        raise InvalidNumber
      }
      match ExactNumber::from_literal(value.to_string()) {
        Some(Repr(coeff~, scale~)) => (coeff, scale)
        _ => raise InvalidNumber
      }
    }
  }
}

///|
fn decimal_power(exponent : Int) -> @bigint.BigInt {
  @bigint.BigInt::from_int(10).pow(@bigint.BigInt::from_int(exponent))
}

///|
fn aligned(
  left : ExactNumber,
  right : ExactNumber,
) -> (@bigint.BigInt, @bigint.BigInt) raise NumericError {
  let (a, sa) = left.parts()
  let (b, sb) = right.parts()
  if sa < sb {
    (a * decimal_power(sb - sa), b)
  } else if sa > sb {
    (a, b * decimal_power(sa - sb))
  } else {
    (a, b)
  }
}

///|
/// Decimal integer predicate; no rounding or floating-point tolerance.
pub fn ExactNumber::is_integer(self : ExactNumber) -> Bool raise NumericError {
  let (coefficient, scale) = self.parts()
  scale <= 0 || coefficient.mod(decimal_power(scale)).is_zero()
}

///|
/// Mathematical equality, including differently spelled decimal numbers.
pub fn ExactNumber::equal(
  self : ExactNumber,
  other : ExactNumber,
) -> Bool raise NumericError {
  let (a, b) = aligned(self, other)
  a == b
}

///|
pub fn ExactNumber::compare(
  self : ExactNumber,
  other : ExactNumber,
) -> Int raise NumericError {
  let (a, b) = aligned(self, other)
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
/// Exact divisibility of aligned integer coefficients, never rounded division.
pub fn ExactNumber::multiple_of(
  self : ExactNumber,
  divisor : ExactNumber,
) -> Bool raise NumericError {
  if divisor.sign() <= 0 {
    return false
  }
  let (a, b) = aligned(self, divisor)
  a.mod(b).is_zero()
}

///|
pub fn ExactNumber::sign(self : ExactNumber) -> Int raise NumericError {
  let (coefficient, _) = self.parts()
  let zero = @bigint.BigInt::from_int(0)
  if coefficient < zero {
    -1
  } else if coefficient > zero {
    1
  } else {
    0
  }
}
