///|
struct Options {
  manifest : String
  output : String
  file : String?
  group : Int?
  case_index : Int?
}

///|
fn options(args : Array[String]) -> Options raise {
  let mut manifest = "benchmark-results/manifest.json"
  let mut output : String? = None
  let mut file = None
  let mut group = None
  let mut case_index = None
  for index = 1; index < args.length(); index = index + 2 {
    guard index + 1 < args.length() else {
      fail("option requires a value: " + args[index])
    }
    let value = args[index + 1]
    match args[index] {
      "--manifest" => manifest = value
      "--output" => output = Some(value)
      "--file" => file = Some(value)
      "--group" => group = Some(@string.parse_int(value))
      "--case" => case_index = Some(@string.parse_int(value))
      _ => fail("unknown option: " + args[index])
    }
  }
  if group is Some(value) && value < 0 {
    fail("negative group index")
  }
  if case_index is Some(value) && value < 0 {
    fail("negative case index")
  }
  let default_output = if file is Some(_) ||
    group is Some(_) ||
    case_index is Some(_) {
    "benchmark-results/conformance-filtered.json"
  } else {
    "benchmark-results/conformance.json"
  }
  {
    manifest,
    output: output.unwrap_or(default_output),
    file,
    group,
    case_index,
  }
}

///|
fn execute(options : Options) -> Int raise {
  let manifest = object(
    @schema.parse(@fs.read_file_to_string(options.manifest)),
  )
  guard count(manifest, "version") == 1 else {
    fail("unsupported manifest version")
  }
  let revision = text(manifest, "revision")
  let root = text(manifest, "suite_root")
  let files = array(manifest, "files")
  guard !files.is_empty() else { fail("empty suite manifest") }
  let filtered = options.file is Some(_) ||
    options.group is Some(_) ||
    options.case_index is Some(_)
  let totals : Map[String, Counts] = {
    "standard": Counts(),
    "optional": Counts(),
    "proposal": Counts(),
  }
  let observed : Map[String, Int] = {
    "standard": 0,
    "optional": 0,
    "proposal": 0,
  }
  let seen : Set[String] = Set([])
  let records : Array[Json] = []
  let groups_report : Array[Json] = []
  for entry in files {
    let metadata = object(entry)
    let path = text(metadata, "path")
    let category = text(metadata, "category")
    guard safe_relative(path) &&
      !seen.contains(path) &&
      totals.contains(category) else {
      fail("invalid or duplicate manifest path/category: " + path)
    }
    seen.add(path)
    guard @schema.parse(@fs.read_file_to_string(root + "/" + path))
      is Array(groups) else {
      fail("fixture is not a group array: " + path)
    }
    guard groups.length() == count(metadata, "groups") else {
      fail("group count mismatch: " + path)
    }
    let mut file_count = 0
    for group_index, group in groups {
      let fields = object(group)
      let description = text(fields, "description")
      guard fields.get("schema") is Some(document) else {
        fail("schema missing: " + path)
      }
      let cases = array(fields, "tests")
      file_count += cases.length()
      let selected = (match options.file {
          None => true
          Some(name) => name == path
        }) &&
        (match options.group {
          None => true
          Some(index) => index == group_index
        })
      if !selected {
        continue
      }
      let compiled : Result[@schema.Schema, @schema.CompileError] = Ok(
        @schema.Schema::compile(document),
      ) catch {
        error => Err(error)
      }
      let group_counts = Counts()
      for case_index, instance in cases {
        let test_fields = object(instance)
        let case_description = text(test_fields, "description")
        let expected = boolean(test_fields, "valid")
        guard test_fields.get("data") is Some(value) else {
          fail("data missing: " + path)
        }
        if options.case_index is Some(index) && index != case_index {
          continue
        }
        let id = path +
          "#" +
          group_index.to_string() +
          "/" +
          case_index.to_string()
        let result : Map[String, Json] = {
          "id": Json::string(id),
          "file": Json::string(path),
          "category": Json::string(category),
          "group": Json::number(group_index.to_double()),
          "case": Json::number(case_index.to_double()),
          "description": Json::string(description),
          "case_description": Json::string(case_description),
          "expected": Json::boolean(expected),
        }
        let status = match compiled {
          Ok(schema) => {
            // Validation exceptions are harness/runtime failures, not silently
            // interpreted as false. Only known schema compile gaps are scored.
            let actual = schema.valid(value)
            let diagnostics_agree = schema.faults(value).is_empty() == actual
            guard diagnostics_agree else {
              fail("valid/faults disagreement: " + id)
            }
            result.set("actual", Json::boolean(actual))
            if actual == expected {
              "pass"
            } else {
              "mismatch"
            }
          }
          Err(error) => {
            result.set("message", Json::string("\{Repr(error)}"))
            compile_status(error)
          }
        }
        result.set("status", Json::string(status))
        totals[category].record(status)
        group_counts.record(status)
        records.push(Json::object(result))
      }
      groups_report.push({
        "file": path,
        "category": category,
        "group": group_index,
        "counts": group_counts.json(),
      })
    }
    guard file_count == count(metadata, "tests") else {
      fail("case count mismatch: " + path)
    }
    observed[category] = observed[category] + file_count
  }
  guard manifest.get("totals") is Some(totals_value) else {
    fail("manifest totals missing")
  }
  let expected_totals = object(totals_value)
  let counts_json : Map[String, Json] = Map([])
  let mut all_matched = true
  for category, counts in totals {
    guard observed[category] == count(expected_totals, category) else {
      fail("manifest total mismatch: " + category)
    }
    if !filtered {
      guard counts.total == observed[category] else {
        fail("unaccounted cases: " + category)
      }
    }
    counts_json.set(category, counts.json())
    if counts.passed != counts.total {
      all_matched = false
    }
  }
  guard !records.is_empty() else { fail("no selected cases") }
  let report : Json = {
    "version": 1,
    "revision": revision,
    "filtered": filtered,
    "status": if all_matched {
      "all_selected_cases_matched"
    } else {
      "coverage_incomplete"
    },
    "counts": Json::object(counts_json),
    "cases": Json::array(records),
    "groups": Json::array(groups_report),
    "optional_format_mode": "annotations_only; format assertion not implemented",
  }
  @fs.write_string_to_file(options.output, report.stringify(indent=2))
  let standard = totals["standard"]
  println(
    "draft2020-12\{if filtered { " (FILTERED)" } else { "" }}: \{standard.passed}/\{standard.total}",
  )
  println("report: \{options.output}")
  if all_matched {
    0
  } else {
    1
  }
}

///|
fn main {
  let status = execute(options(@env.args())) catch {
    error => {
      println("HARNESS ERROR: \{error}")
      2
    }
  }
  @sys.exit(status)
}
