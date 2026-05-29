name = "colmugx/mcp"

version = "1.0.0"

import {
  "moonbitlang/async@0.16.5",
}

options(
  readme: "README.mbt.md",
  repository: "https://github.com/colmugx/mcp.mbt",
  license: "Apache-2.0",
  keywords: [ "mcp", "modelcontextprotocol" ],
  description: "Type-safe MCP SDK in MoonBit with server/client support and dual transport (STDIO/HTTP)",
  source: "src",
  exclude: [ "examples" ],
  "preferred-target": "native",
)
