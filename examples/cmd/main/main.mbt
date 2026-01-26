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
  let server = @mcp.MCPServer::new("moon-notes", "1.0.0")
  @internal.register_tools(server, storage)
  @internal.register_resources(server, storage)
  @internal.register_prompts(server, storage)
  let transport = @mcp.AnyTransport::Stdio(@mcp.StdioTransport::new())
  server.run(transport) catch {
    e => println("\n❌ Server error: \{e}")
  }
}
