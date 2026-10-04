///|
/// Validate two JSON arguments. Exit 0 = valid, 1 = mismatch, 2 = error/usage.
fn main {
  let args = @env.args()
  if args.length() < 3 || args[args.length() - 1] == "--help" {
    println("Usage: json-schema '<schema-json>' '<instance-json>'")
    println(
      "Exit codes: 0 valid; 1 validation mismatch; 2 malformed/unsupported input",
    )
    @sys.exit(2)
  }
  let status = try {
    let document = @schema.parse(args[args.length() - 2])
    let value = @schema.parse(args[args.length() - 1])
    let compiled = @schema.Schema::compile(document)
    let failures = compiled.faults(value)
    if failures.is_empty() {
      println("valid")
      0
    } else {
      for failure in failures {
        println(
          "\{failure.instance_path} [\{failure.keyword}] \{failure.message} (schema \{failure.schema_path})",
        )
      }
      1
    }
  } catch {
    error => {
      println("error: \{error}")
      2
    }
  }
  @sys.exit(status)
}
