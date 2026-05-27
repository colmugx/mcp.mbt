name = "colmugx/mcp"

version = "0.5.2"

import {
  "moonbitlang/async@0.16.5",
}

options(
  readme: "README.mbt.md",
  repository: "https://github.com/colmugx/mcp.mbt",
  license: "Apache-2.0",
  keywords: [ "mcp", "modelcontextprotocol" ],
  description: "Type-safe MCP server implementation in MoonBit with dual transport support (STDIO/HTTP)",
  source: "src",
  exclude: [ "examples" ],
  "preferred-target": "native",
)