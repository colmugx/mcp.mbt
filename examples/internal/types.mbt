///|
pub(all) struct Note {
  title : String
  content : String
  tags : Array[String]
} derive(Eq, Show)

///|
fn find_substring(haystack : String, needle : String, start : Int) -> Int? {
  let needle_len = needle.length()
  if needle_len == 0 {
    return Some(start)
  }
  let mut i = start
  while i <= haystack.length() - needle_len {
    let mut j = 0
    let mut found = true
    while j < needle_len {
      if haystack[i + j] != needle[j] {
        found = false
        break
      }
      j = j + 1
    }
    if found {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn extract_substring(s : String, start : Int, end : Int) -> String {
  let mut result = ""
  let mut i = start
  while i < end {
    result = result + s[i].to_string()
    i = i + 1
  }
  result
}

///|
pub fn json_string(s : String) -> String {
  let mut result = "\""
  let mut i = 0
  while i < s.length() {
    let ch = s[i]
    match ch {
      '"' => result = result + "\\\""
      '\\' => result = result + "\\\\"
      '\n' => result = result + "\\n"
      '\r' => result = result + "\\r"
      '\t' => result = result + "\\t"
      _ => result = result + ch.to_string()
    }
    i = i + 1
  }
  result = result + "\""
  result
}

///|
pub fn json_array_strings(arr : Array[String]) -> String {
  let mut result = "["
  let mut first = true
  for tag in arr {
    if not(first) {
      result = result + ","
    }
    result = result + json_string(tag)
    first = false
  }
  result = result + "]"
  result
}

///|
pub fn Note::to_json(self : Note) -> String {
  let result = "{" +
    "\"title\":" +
    json_string(self.title) +
    "," +
    "\"content\":" +
    json_string(self.content) +
    "," +
    "\"tags\":" +
    json_array_strings(self.tags) +
    "}"
  result
}

///|
pub fn Note::from_json(json_str : String) -> Result[Note, String] {
  let title = match extract_json_field(json_str, "title") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let content = match extract_json_field(json_str, "content") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let tags_json = match extract_json_array(json_str, "tags") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let tags = parse_string_array(tags_json)
  Ok(Note::{ title, content, tags })
}

///|
fn extract_json_field(
  json_str : String,
  field : String,
) -> Result[String, String] {
  let field_key = "\"" + field + "\":\""
  match find_substring(json_str, field_key, 0) {
    None => Err("Field '" + field + "' not found in JSON")
    Some(start) => {
      let value_start = start + field_key.length()
      match find_substring(json_str, "\"", value_start) {
        None => Err("Unterminated string for field '" + field + "'")
        Some(end) => Ok(extract_substring(json_str, value_start, end))
      }
    }
  }
}

///|
fn extract_json_array(
  json_str : String,
  field : String,
) -> Result[String, String] {
  let field_key = "\"" + field + "\":"
  match find_substring(json_str, field_key, 0) {
    None => Err("Field '" + field + "' not found in JSON")
    Some(start) => {
      let array_start = start + field_key.length()
      if json_str[array_start] != '[' {
        return Err("Field '" + field + "' is not an array")
      }
      let mut depth = 0
      let mut i = array_start
      while i < json_str.length() {
        match json_str[i] {
          '[' => depth = depth + 1
          ']' => {
            depth = depth - 1
            if depth == 0 {
              let arr_content = extract_substring(json_str, array_start, i + 1)
              return Ok(arr_content)
            }
          }
          _ => ()
        }
        i = i + 1
      }
      Err("Unterminated array for field '" + field + "'")
    }
  }
}

///|
fn parse_string_array(arr_str : String) -> Array[String] {
  let result : Array[String] = []
  let mut i = 1
  while i < arr_str.length() {
    match arr_str[i] {
      ' ' | ',' | ']' => {
        i = i + 1
        continue
      }
      '"' => {
        let mut value = ""
        i = i + 1
        while i < arr_str.length() && arr_str[i] != '"' {
          if arr_str[i] == '\\' && i + 1 < arr_str.length() {
            match arr_str[i + 1] {
              '"' => value = value + "\""
              '\\' => value = value + "\\"
              'n' => value = value + "\n"
              'r' => value = value + "\r"
              't' => value = value + "\t"
              _ => value = value + arr_str[i + 1].to_string()
            }
            i = i + 2
          } else {
            value = value + arr_str[i].to_string()
            i = i + 1
          }
        }
        result.push(value)
        i = i + 1
      }
      _ => i = i + 1
    }
  }
  result
}
