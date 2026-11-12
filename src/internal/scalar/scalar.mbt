///|
/// Highest digit place of a canonical digit run: the exponent shift that turns
/// the run into an integer. Canonical digits are never empty, so
/// `digits_length >= 1` is the representation invariant the callers rely on.
///
/// Keep this package free of `Map`/`Json` imports: `moon prove` cannot lower
/// them, and an import here would take the contracts out of the proof.
pub fn decimal_highest_place(
  digits_length : Int32,
) -> Int32 where {
  proof_require: digits_length >= 1,
  proof_ensure: result => result == digits_length - 1,
  proof_ensure: result => result >= 0,
} {
  digits_length - 1
}

///|
/// Ordering of two canonical digit runs whose highest place already agrees:
/// after the shared prefix the longer run carries the extra value, because
/// canonical digits never end in zero and a zero suffix cannot exist.
pub fn decimal_tail_order(
  left_length : Int32,
  right_length : Int32,
) -> Int32 where {
  proof_require: left_length >= 1,
  proof_require: right_length >= 1,
  proof_ensure: result => result == left_length - right_length,
  proof_ensure: result => (result == 0) == (left_length == right_length),
  proof_ensure: result => (result > 0) == (left_length > right_length),
} {
  left_length - right_length
}
