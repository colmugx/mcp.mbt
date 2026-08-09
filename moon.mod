name = "colmugx/mcp"

version = "0.15.0"

import {
  "moonbitlang/async@0.20.4",
  "cc06b/mooncry@0.13.1",
  "Tigls/mb-getrandom@0.1.0",
}

readme = "README.mbt.md"

repository = "https://github.com/colmugx/mcp.mbt"

license = "Apache-2.0"

keywords = [ "mcp", "modelcontextprotocol" ]

description = "Type-safe MCP SDK in MoonBit with server/client support and dual transport (STDIO/HTTP)"

preferred_target = "native"

source = "src"

options(
  exclude: [ "examples", "public", "docs" ],
)
