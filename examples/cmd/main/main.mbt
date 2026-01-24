///|

///| MCP Server Example - Simple Entry Point

///|
/// Demonstrates basic MCP server startup with STDIO transport
async fn main {
  println("Starting MCP Server Example...")

  // Create server instance
  let server = @server.MCPServer::new("mcp-example-server", "1.0.0")

  // Register tools
  println("Registering tools...")
  server.register_trait_tool(@lib.EchoTool::{  })
  server.register_trait_tool(@lib.CalculateTool::{  })
  server.register_trait_tool(@lib.TransformTextTool::{  })
  server.register_trait_tool(@lib.AnalyzeTextTool::{  })
  server.register_trait_tool(@lib.GetTimestampTool::{  })
  println("5 tools registered successfully.")

  // Use STDIO transport
  let transport = @transport.AnyTransport::Stdio(
    @transport.StdioTransport::new(),
  )
  println("Server started with STDIO transport. Waiting for requests...")

  // Run server
  server.run(transport) catch {
    e => println("Server error: " + e.to_string())
  }
  println("Server stopped.")
}
