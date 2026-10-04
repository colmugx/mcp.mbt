// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "colmugx/json-schema"

version = "0.1.0"

readme = "README.mbt.md"

repository = ""

license = "Apache-2.0"

keywords = [ "json-schema", "validation", "jsonschema", "schema" ]

preferred_target = "wasm"

description = "Compile-once JSON Schema 2020-12 validator for MoonBit: exact decimal arithmetic, precise pattern semantics, no silent schema errors, no hidden I/O."

import {
  "moonbitlang/regexp@0.3.5",
  "moonbitlang/x@0.5.5",
}
