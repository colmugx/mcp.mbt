///|
test "runner: every instance has one status and remains in denominator" {
  let counts = Counts()
  for status in ["pass", "mismatch", "unsupported", "rejected"] {
    counts.record(status)
  }
  assert_eq(counts.total, 4)
  assert_eq(
    counts.passed + counts.mismatch + counts.unsupported + counts.rejected,
    counts.total,
  )
  try counts.record("skip") catch {
    _ => ()
  } noraise {
    _ => fail("unknown status must fail")
  }
  assert_eq(counts.total, 4)
}

///|
test "runner: filters cannot overwrite the default complete report" {
  let selection = options([
    "runner", "--file", "type.json", "--group", "0", "--case", "1",
  ])
  assert_eq(selection.output, "benchmark-results/conformance-filtered.json")
  assert_eq(options(["runner"]).output, "benchmark-results/conformance.json")
  assert_true(safe_relative("optional/format/date.json"))
  for path in ["", "/tmp/x", "../x", "optional/../x", "a\\b", "a//b"] {
    assert_false(safe_relative(path))
  }
}
