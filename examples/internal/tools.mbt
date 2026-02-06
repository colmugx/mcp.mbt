///|
fn get_string(json : Json, key : String) -> String? {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
fn get_array(
  json : Json,
  key : String,
) -> Result[Array[Json], @tool.ToolResult] {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(Array(arr)) => Ok(arr)
        Some(_) =>
          Err(@tool.ToolResult::error("Field '\{key}' is not an array"))
        None => Err(@tool.ToolResult::error("Missing field '\{key}'"))
      }
    _ => Err(@tool.ToolResult::error("Expected JSON object"))
  }
}

///|
fn array_param(
  name : String,
  description : String,
  _item_type : String,
) -> @tool.ParamDef {
  { name, description, type_: "array", required: false }
}

///|
/// NEW STYLE (0.4): struct-as-schema with tool_fn
/// Define params struct with derive(ToJson, FromJson)
struct CreateNoteParams {
  title : String
  content : String
  tags : Array[String]?
} derive(ToJson, FromJson)

///|
/// Implement Params trait - this is the "struct即schema" design
pub impl @mcp_core.Params for CreateNoteParams with schema() -> @mcp_core.JsonSchema {
  @mcp_core.schema_builder()
  .field("title", @mcp_core.str_type(), required=true, desc="Note title")
  .field("content", @mcp_core.str_type(), required=true, desc="Note content")
  .field("tags", @mcp_core.arr_type(@mcp_core.str_type()), desc="Optional tags")
  .build(desc="Create a new note")
}

///|
pub impl @mcp_core.Params for CreateNoteParams with from_json(j : Json) -> CreateNoteParams raise @mcp_core.ToolError {
  match j {
    Object(obj) => {
      let title = match obj.get("title") {
        Some(String(s)) => s
        _ => raise @mcp_core.tool_error("Missing or invalid 'title'")
      }
      let content = match obj.get("content") {
        Some(String(s)) => s
        _ => raise @mcp_core.tool_error("Missing or invalid 'content'")
      }
      let tags = match obj.get("tags") {
        Some(Array(arr)) => {
          let tags_arr : Array[String] = []
          for item in arr {
            match item {
              String(s) => tags_arr.push(s)
              _ => raise @mcp_core.tool_error("Invalid tag (must be string)")
            }
          }
          Some(tags_arr)
        }
        Some(Null) | None => None
        _ => raise @mcp_core.tool_error("Invalid 'tags' (must be array)")
      }
      { title, content, tags }
    }
    _ => raise @mcp_core.tool_error("Expected JSON object")
  }
}

///|
pub impl @mcp_core.Params for CreateNoteParams with to_json(
  self : CreateNoteParams,
) -> Json {
  let obj : Map[String, Json] = {}
  obj.set("title", Json::string(self.title))
  obj.set("content", Json::string(self.content))
  match self.tags {
    Some(tags) =>
      obj.set("tags", Json::array(tags.map(fn(s) { Json::string(s) })))
    None => ()
  }
  Json::object(obj)
}

///|
pub(all) struct CreateNoteTool {
  storage : Storage
}

///|
pub fn CreateNoteTool::new(storage : Storage) -> CreateNoteTool {
  { storage, }
}

///|
pub impl @tool.Tool for CreateNoteTool with name(_self : CreateNoteTool) -> String {
  "create_note"
}

///|
pub impl @tool.Tool for CreateNoteTool with description(_self : CreateNoteTool) -> String {
  "Create a new note with title, content, and optional tags"
}

///|
pub impl @tool.Tool for CreateNoteTool with params(_self : CreateNoteTool) -> Array[
  @tool.ParamDef,
] {
  [
    {
      name: "title",
      description: "Note title",
      type_: "string",
      required: true,
    },
    {
      name: "content",
      description: "Note content",
      type_: "string",
      required: true,
    },
    {
      name: "tags",
      description: "Optional tags",
      type_: "array",
      required: false,
    },
  ]
}

///|
pub impl @tool.Tool for CreateNoteTool with execute(_self, args) {
  try {
    // Explicit call to Params trait
    let params : CreateNoteParams = @mcp_core.Params::from_json(args)
    let note : Note = {
      title: params.title,
      content: params.content,
      tags: params.tags.unwrap_or(([] : Array[String])),
    }
    match _self.storage.save_note(note) {
      Ok(_) => @tool.ToolResult::text("✅ Note created: \{params.title}")
      Err(msg) => @tool.ToolResult::text("Failed: \{msg}")
    }
  } catch {
    @mcp_core.ToolError(msg) =>
      @tool.ToolResult::error("Parameter error: " + msg)
    _ => @tool.ToolResult::error("Unknown error")
  }
}

///|
pub(all) struct ReadNoteTool {
  storage : Storage
}

///|
pub fn ReadNoteTool::new(storage : Storage) -> ReadNoteTool {
  { storage, }
}

///|
pub impl @tool.Tool for ReadNoteTool with name(_self : ReadNoteTool) -> String {
  "read_note"
}

///|
pub impl @tool.Tool for ReadNoteTool with description(_self : ReadNoteTool) -> String {
  "Read a note by title"
}

///|
pub impl @tool.Tool for ReadNoteTool with params(_self : ReadNoteTool) -> Array[
  @tool.ParamDef,
] {
  [
    {
      name: "title",
      description: "Note title to read (required)",
      type_: "string",
      required: true,
    },
  ]
}

///|
async fn read_note_execute(
  _self : ReadNoteTool,
  args : Json,
) -> @tool.ToolResult {
  let title_p = match get_string(args, "title") {
    Some(t) => t
    None => return @tool.ToolResult::error("Missing required parameter 'title'")
  }
  match _self.storage.load_note(title_p) {
    Ok(note) => {
      let tags_joined = note.tags.join(", ")
      let tags_text = if note.tags.length() > 0 {
        "Tags: \{tags_joined}\n\n"
      } else {
        ""
      }
      @tool.ToolResult::text("# \{note.title}\n\n" + tags_text + note.content)
    }
    Err(msg) => @tool.ToolResult::error(msg)
  }
}

///|
pub impl @tool.Tool for ReadNoteTool with execute(_self, args) {
  read_note_execute(_self, args)
}

///|
pub(all) struct ListNotesTool {
  storage : Storage
}

///|
pub fn ListNotesTool::new(storage : Storage) -> ListNotesTool {
  { storage, }
}

///|
pub impl @tool.Tool for ListNotesTool with name(_self : ListNotesTool) -> String {
  "list_notes"
}

///|
pub impl @tool.Tool for ListNotesTool with description(_self : ListNotesTool) -> String {
  "List all available notes"
}

///|
pub impl @tool.Tool for ListNotesTool with params(_self : ListNotesTool) -> Array[
  @tool.ParamDef,
] {
  []
}

///|
async fn list_notes_execute(
  _self : ListNotesTool,
  _args : Json,
) -> @tool.ToolResult {
  match _self.storage.list_notes() {
    Ok(titles) =>
      if titles.length() == 0 {
        @tool.ToolResult::text("No notes found. Create one with create_note!")
      } else {
        let list_text = titles.map(fn(t) { "• \{t}" }).join("\n")
        @tool.ToolResult::text(
          "📝 Notes (\{titles.length()}):\n\n\{list_text}",
        )
      }
    Err(msg) => @tool.ToolResult::error(msg)
  }
}

///|
pub impl @tool.Tool for ListNotesTool with execute(_self, args) {
  list_notes_execute(_self, args)
}

///|
pub(all) struct DeleteNoteTool {
  storage : Storage
}

///|
pub fn DeleteNoteTool::new(storage : Storage) -> DeleteNoteTool {
  { storage, }
}

///|
pub impl @tool.Tool for DeleteNoteTool with name(_self : DeleteNoteTool) -> String {
  "delete_note"
}

///|
pub impl @tool.Tool for DeleteNoteTool with description(_self : DeleteNoteTool) -> String {
  "Delete a note by title"
}

///|
pub impl @tool.Tool for DeleteNoteTool with params(_self : DeleteNoteTool) -> Array[
  @tool.ParamDef,
] {
  [
    {
      name: "title",
      description: "Note title to delete (required)",
      type_: "string",
      required: true,
    },
  ]
}

///|
async fn delete_note_execute(
  _self : DeleteNoteTool,
  args : Json,
) -> @tool.ToolResult {
  let title_p = match get_string(args, "title") {
    Some(t) => t
    None => return @tool.ToolResult::error("Missing required parameter 'title'")
  }
  match _self.storage.delete_note(title_p) {
    Ok(_) => @tool.ToolResult::text("✅ Note deleted successfully: \{title_p}")
    Err(msg) => @tool.ToolResult::error(msg)
  }
}

///|
pub impl @tool.Tool for DeleteNoteTool with execute(_self, args) {
  delete_note_execute(_self, args)
}

///|
pub(all) struct SyncNotesTool {
  storage : Storage
}

///|
pub fn SyncNotesTool::new(storage : Storage) -> SyncNotesTool {
  { storage, }
}

///|
pub impl @tool.Tool for SyncNotesTool with name(_self : SyncNotesTool) -> String {
  "sync_notes"
}

///|
pub impl @tool.Tool for SyncNotesTool with description(_self : SyncNotesTool) -> String {
  "Sync all notes to a GitHub Gist (requires GITHUB_TOKEN environment variable)"
}

///|
pub impl @tool.Tool for SyncNotesTool with params(_self : SyncNotesTool) -> Array[
  @tool.ParamDef,
] {
  []
}

///|
async fn sync_notes_execute(
  _self : SyncNotesTool,
  _args : Json,
) -> @tool.ToolResult {
  // Get GitHub token from environment
  match @sys.get_env_var("GITHUB_TOKEN") {
    None =>
      @tool.ToolResult::error(
        "GITHUB_TOKEN environment variable not set. " +
        "Set it to sync notes to GitHub Gist.",
      )
    Some(token) =>
      // Load all notes
      match _self.storage.list_notes() {
        Err(msg) => @tool.ToolResult::error("Failed to list notes: \{msg}")
        Ok(titles) => {
          // Build Gist JSON payload
          let files_map : Map[String, Json] = Map::default()
          for title in titles {
            match _self.storage.load_note(title) {
              Ok(note) => {
                let filename = title + ".md"
                let file_content = note.to_json()
                let file_obj : Map[String, Json] = Map::default()
                file_obj.set("content", Json::string(file_content))
                files_map.set(filename, Json::object(file_obj))
              }
              Err(_) => () // Skip failed note loads
            }
          }
          let timestamp = 0
          let description = "MoonNotes backup - \{timestamp}"

          // Create full Gist payload
          let gist_map : Map[String, Json] = Map::default()
          gist_map.set("description", Json::string(description))
          gist_map.set("public", Json::boolean(false))
          gist_map.set("files", Json::object(files_map))
          let payload = Json::object(gist_map).to_string()

          // Make HTTP POST request to GitHub Gist API
          let url_gist = "https://api.github.com/gists"
          let headers : Map[String, String] = Map::default()
          headers.set("Authorization", "token \{token}")
          headers.set("Accept", "application/vnd.github+json")
          headers.set("Content-Type", "application/json")
          let (response, body) = @http.post(url_gist, payload, headers~)
          if response.code == 201 {
            let response_json = body.json()
            match response_json {
              Object(gist_obj) =>
                match gist_obj.get("html_url") {
                  Some(String(html_url)) =>
                    @tool.ToolResult::text(
                      "✅ Notes synced successfully!\n\nGist URL: \{html_url}",
                    )
                  _ => @tool.ToolResult::text("✅ Notes synced successfully!")
                }
              _ => @tool.ToolResult::text("✅ Notes synced successfully!")
            }
          } else if response.code == 401 {
            @tool.ToolResult::error(
              "GitHub authentication failed. Check GITHUB_TOKEN.",
            )
          } else {
            let error_msg = "GitHub API error (code: \{response.code})"
            @tool.ToolResult::error(error_msg)
          }
        }
      }
  }
}

///|
pub impl @tool.Tool for SyncNotesTool with execute(_self, args) {
  sync_notes_execute(_self, args)
}

///|
pub fn register_tools(
  server : @mcp.MCPServer,
  storage : Storage,
) -> @mcp.MCPServer {
  server
  |> @mcp.MCPServer::with_tool(CreateNoteTool::new(storage))
  |> @mcp.MCPServer::with_tool(ReadNoteTool::new(storage))
  |> @mcp.MCPServer::with_tool(ListNotesTool::new(storage))
  |> @mcp.MCPServer::with_tool(DeleteNoteTool::new(storage))
  |> @mcp.MCPServer::with_tool(SyncNotesTool::new(storage))
}
