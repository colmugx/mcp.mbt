///|
pub(all) struct SummarizeNotePrompt {
  storage : Storage
}

///|
pub impl @prompt.Prompt for SummarizeNotePrompt with name(
  _self : SummarizeNotePrompt,
) -> String {
  "summarize_note"
}

///|
pub impl @prompt.Prompt for SummarizeNotePrompt with description(
  _self : SummarizeNotePrompt,
) -> String {
  "Generate a summary prompt for a specific note"
}

///|
pub impl @prompt.Prompt for SummarizeNotePrompt with arguments(
  _self : SummarizeNotePrompt,
) -> Array[@types.PromptArgument] {
  [
    {
      name: "note_title",
      description: Some("Title of the note to summarize"),
      required: Some(true),
    },
  ]
}

///|
async fn summarize_note_get(
  _self : SummarizeNotePrompt,
  args : Json,
) -> Result[@types.GetPromptResult, @types.MCPError] {
  let note_title = match get_string(args, "note_title") {
    None =>
      return Err(
        @types.MCPError::InvalidParams("Missing 'note_title' parameter"),
      )
    Some(nt) => nt
  }

  // Load note from storage
  match _self.storage.load_note(note_title) {
    Err(e) => Err(@types.MCPError::InternalError("Failed to load note: \{e}"))
    Ok(note) => {
      // Generate summary prompt with note content
      let tags_joined = note.tags.join(", ")
      let prompt_content = "Please summarize the following note:\n\n" +
        "Title: \{note.title}\n" +
        "Content:\n\{note.content}\n\n" +
        "Tags: \{tags_joined}"
      Ok(@types.GetPromptResult::{
        description: Some("Summary prompt for note: \{note.title}"),
        messages: [
          {
            role: "system",
            content: @tool.ContentItem::Text(
              "You are a helpful assistant that summarizes notes concisely and accurately.",
            ),
          },
          { role: "user", content: @tool.ContentItem::Text(prompt_content) },
        ],
      })
    }
  }
}

///|
pub impl @prompt.Prompt for SummarizeNotePrompt with get(_self, args) {
  summarize_note_get(_self, args)
}

///|
pub fn register_prompts(
  server : @mcp.MCPServer,
  storage : Storage,
) -> @mcp.MCPServer {
  server.with_prompt(SummarizeNotePrompt::{ storage, })
}
