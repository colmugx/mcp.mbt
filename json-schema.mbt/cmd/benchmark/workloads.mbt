///|
struct Instance {
  id : String
  value : Json
  expected : Bool
}

///|
struct Group {
  document : Json
  compiled : @schema.Schema
  instances : Array[Instance]
}

///|
struct Workload {
  groups : Array[Group]
  ids : Array[String]
  excluded : Int
}

///|
fn object(value : Json) -> Map[String, Json] raise {
  guard value is Object(fields) else { fail("expected object") }
  fields
}

///|
fn text(fields : Map[String, Json], key : String) -> String raise {
  guard fields.get(key) is Some(String(value)) else {
    fail("missing string: " + key)
  }
  value
}

///|
fn integer(fields : Map[String, Json], key : String) -> Int raise {
  guard fields.get(key) is Some(Number(value, ..)) &&
    value >= 0 &&
    value <= 2147483647.0 &&
    value.floor() == value else {
    fail("invalid count: " + key)
  }
  value.to_int()
}

///|
fn official(manifest_path : String, result_path : String) -> Workload raise {
  let manifest = object(@json.parse(@fs.read_file_to_string(manifest_path)))
  let result = object(@json.parse(@fs.read_file_to_string(result_path)))
  guard integer(manifest, "version") == 1 &&
    integer(result, "version") == 1 &&
    manifest.get("revision") == result.get("revision") &&
    result.get("filtered") == Some(Json::boolean(false)) else {
    fail("invalid conformance identity/version")
  }
  guard result.get("cases") is Some(Array(records)) &&
    manifest.get("totals") is Some(Object(totals)) &&
    manifest.get("files") is Some(Array(files)) else {
    fail("missing corpus evidence")
  }
  let allowed : Set[String] = Set([])
  let mut standard_total = 0
  for record in records {
    let fields = object(record)
    if text(fields, "category") == "standard" {
      standard_total += 1
      if text(fields, "status") == "pass" {
        let id = text(fields, "id")
        guard !allowed.contains(id) else { fail("duplicate eligible case") }
        allowed.add(id)
      }
    }
  }
  guard standard_total == integer(totals, "standard") && !allowed.is_empty() else {
    fail("unaccounted or empty performance corpus")
  }
  let root = text(manifest, "suite_root")
  let groups : Array[Group] = []
  let ids : Array[String] = []
  for entry in files {
    let metadata = object(entry)
    if text(metadata, "category") != "standard" {
      continue
    }
    let path = text(metadata, "path")
    guard !path.has_prefix("/") &&
      !path.contains("\\") &&
      !path.split("/").any(part => part == ".." || part.is_empty()) else {
      fail("unsafe fixture path")
    }
    guard @schema.parse(@fs.read_file_to_string(root + "/" + path))
      is Array(source_groups) else {
      fail("invalid fixture")
    }
    for group_index, raw in source_groups {
      let fields = object(raw)
      guard fields.get("tests") is Some(Array(cases)) &&
        fields.get("schema") is Some(document) else {
        fail("invalid test group")
      }
      let instances : Array[Instance] = []
      for case_index, raw_case in cases {
        let id = path +
          "#" +
          group_index.to_string() +
          "/" +
          case_index.to_string()
        if !allowed.contains(id) {
          continue
        }
        let fields = object(raw_case)
        guard fields.get("data") is Some(value) else {
          fail("missing instance")
        }
        let expected = match fields.get("valid") {
          Some(True) => true
          Some(False) => false
          _ => fail("invalid expectation")
        }
        instances.push({ id, value, expected, })
        ids.push(id)
      }
      if instances.is_empty() {
        continue
      }
      groups.push({
        document,
        compiled: @schema.Schema::compile(document),
        instances,
      })
    }
  }
  guard ids.length() == allowed.length() else {
    fail("eligible cases missing from original corpus")
  }
  { groups, ids, excluded: standard_total - allowed.length(), }
}

///|
fn fixed_group(
  name : String,
  document : Json,
  values : Array[(Json, Bool)],
) -> Workload raise {
  let instances = values.mapi((index, entry) => {
    let (value, expected) = entry
    { id: "synthetic/" + name + "/" + index.to_string(), value, expected, }
  })
  {
    groups: [
      { document, compiled: @schema.Schema::compile(document), instances, },
    ],
    ids: instances.map(value => value.id),
    excluded: 0,
  }
}

///|
fn synthetic(name : String) -> Workload raise {
  let document = match name {
    "tool_arguments" =>
      "{\"type\":\"object\",\"required\":[\"amount\",\"name\"],\"properties\":{\"amount\":{\"multipleOf\":0.1},\"name\":{\"type\":\"string\",\"pattern\":\"^[A-Za-z_][A-Za-z0-9_]*$\"}},\"additionalProperties\":false}"
    "structured_result" =>
      "{\"type\":\"object\",\"required\":[\"items\"],\"properties\":{\"items\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"id\",\"text\"],\"properties\":{\"id\":{\"type\":\"integer\"},\"text\":{\"type\":\"string\"}},\"additionalProperties\":false}}},\"additionalProperties\":false}"
    "array1024" =>
      "{\"type\":\"array\",\"items\":{\"type\":\"integer\",\"minimum\":0},\"minItems\":1024,\"maxItems\":1024}"
    "unique128" => "{\"type\":\"array\",\"uniqueItems\":true}"
    "branches" =>
      "{\"anyOf\":[{\"type\":\"object\",\"required\":[\"x\"]},{\"type\":\"string\",\"pattern\":\"^x+$\"},{\"type\":\"array\",\"contains\":{\"type\":\"integer\"}},{\"type\":\"integer\",\"multipleOf\":2}]}"
    "exact_decimal" => "{\"type\":\"integer\",\"multipleOf\":1}"
    "pattern" =>
      "{\"type\":\"string\",\"pattern\":\"^(?=.{3}$)(?!000)\\\\d+$\"}"
    _ => fail("unknown scenario: " + name)
  }
  let values : Array[(Json, Bool)] = match name {
    "tool_arguments" =>
      [
        (@schema.parse("{\"amount\":0.3,\"name\":\"tool_1\"}"), true),
        (@schema.parse("{\"amount\":0.31,\"name\":\"tool_1\"}"), false),
        (
          @schema.parse("{\"amount\":0.3,\"name\":\"tool_1\",\"extra\":1}"),
          false,
        ),
      ]
    "structured_result" =>
      [
        (
          @schema.parse(
            "{\"items\":[{\"id\":1,\"text\":\"hello\"},{\"id\":2,\"text\":\"世界\"}]}",
          ),
          true,
        ),
        (@schema.parse("{\"items\":[{\"id\":1,\"text\":false}]}"), false),
      ]
    "array1024" =>
      [
        (
          Json::array(
            Array::makei(1024, index => Json::number(index.to_double())),
          ),
          true,
        ),
      ]
    "unique128" =>
      [
        (
          Json::array(
            Array::makei(128, index => Json::number(index.to_double())),
          ),
          true,
        ),
        (Json::array([Json::number(1), Json::number(1)]), false),
      ]
    "branches" =>
      [
        (@schema.parse("18"), true),
        (@schema.parse("19"), false),
        (@schema.parse("[null,1]"), true),
      ]
    "exact_decimal" =>
      [
        (@schema.parse("1.00000000000000000000000000001"), false),
        (@schema.parse("9007199254740993"), true),
        (@schema.parse("1000000000.5"), false),
      ]
    "pattern" =>
      [
        (Json::string("123"), true),
        (Json::string("000"), false),
        (Json::string("1234"), false),
      ]
    _ => fail("unknown scenario")
  }
  fixed_group(name, @schema.parse(document), values)
}
