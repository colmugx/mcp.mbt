///|
fn ends_with_md(s : String) -> Bool {
  let len = s.length()
  if len < 3 {
    return false
  }
  s[len - 3] == '.' && s[len - 2] == 'm' && s[len - 1] == 'd'
}

///|
fn remove_md_extension(s : String) -> String {
  let len = s.length()
  if len < 3 {
    return s
  }
  let mut result = ""
  let mut i = 0
  while i < len - 3 {
    result = result + s[i].to_string()
    i = i + 1
  }
  result
}

///|
pub(all) struct Storage {
  base_dir : String
}

///|
pub fn Storage::new(base_dir : String) -> Storage {
  { base_dir, }
}

///|
pub async fn Storage::init(self : Storage) -> Result[Unit, String] {
  if not(@fs.exists(self.base_dir)) {
    let _ = try? @fs.mkdir(self.base_dir, permission=0o755)

  }
  Ok(())
}

///|
pub async fn Storage::save_note(
  self : Storage,
  note : Note,
) -> Result[Unit, String] {
  let file_path = "\{self.base_dir}/\{note.title}.md"

  // Convert note to JSON and write to file
  let json_content = note.to_json()
  let bytes = @encoding/utf8.encode(json_content)
  let _ = try? @fs.write_file(file_path, bytes, create=0o644)
  Ok(())
}

///|
pub async fn Storage::load_note(
  self : Storage,
  title : String,
) -> Result[Note, String] {
  let file_path = "\{self.base_dir}/\{title}.md"
  if not(@fs.exists(file_path)) {
    return Err("Note not found: " + title)
  }
  let data = @fs.read_file(file_path)
  let json_content = data.text()
  match Note::from_json(json_content) {
    Ok(note) => Ok(note)
    Err(e) => Err("Failed to parse note: " + e)
  }
}

///|
pub async fn Storage::list_notes(
  self : Storage,
) -> Result[Array[String], String] {
  if not(@fs.exists(self.base_dir)) {
    return Ok([])
  }
  let entries = @fs.readdir(
    self.base_dir,
    include_hidden=false,
    include_special=false,
  )
  let titles : Array[String] = []
  for entry in entries {
    if ends_with_md(entry) {
      let title = remove_md_extension(entry)
      titles.push(title)
    }
  }
  Ok(titles)
}

///|
pub async fn Storage::delete_note(
  self : Storage,
  title : String,
) -> Result[Unit, String] {
  let file_path = "\{self.base_dir}/\{title}.md"
  if not(@fs.exists(file_path)) {
    return Err("Note not found: " + title)
  }
  let _ = try? @fs.remove(file_path)
  Ok(())
}
