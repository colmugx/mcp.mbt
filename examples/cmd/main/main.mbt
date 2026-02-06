///|
async fn main {
  println("🚀 Starting MoonNotes MCP Server...")
  let storage = @internal.Storage::new("notes")
  match storage.init() {
    Ok(_) => println("✅ Storage initialized successfully")
    Err(e) => {
      println("❌ Failed to initialize storage: \{e}")
      @sys.exit(1)
    }
  }
  let server = @mcp.mcp_server(name="moon-notes", version="1.0.0")
    |> @internal.register_tools(storage)
    |> @internal.register_resources(storage)
    |> @internal.register_prompts(storage)
  @async.with_task_group(async fn(group) { server.run_http(port=4042, group~) })
}
