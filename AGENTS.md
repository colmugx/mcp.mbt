# mcp.mbt

实现之前，请仔细思考：你的实现是否符合函数式思想
写注释之前，请仔细思考：注释信息对未来的迭代或者HANDOFF是否有必要

## Commands

```bash
moon check --target native --output-json   # type check (also runs in pre-commit hook)
moon test  --target native --output-json   # all root tests
moon test --target native --output-json -f 't05*'  # filter by glob
moon check --target js --output-json       # js gate (CI also runs js check+test)
moon test  --target js --output-json       # js suite incl. real child-process tests
moon test --update                         # refresh snapshots
moon fmt                                   # format all code
moon info                                  # update .mbti generated interface
moon coverage analyze                      # coverage report (redirect explicitly if needed)
```

> **IMPORTANT**: All `moon check`/`test`/`build` commands MUST use `--output-json`
> so diagnostics are machine-readable and test counts are captured. Always pass
> `--target native` for the primary gate (default target runs sync tests only).

> **Target gating**: in `src/transport/moon.pkg`, `stdio.mbt`/`stdio_client.mbt`/
> `http_server.mbt` and their I/O tests are `native`+`wasm` only (async has no js
> implementation for stdio/process/socket/http-server); js gets stubs from
> `unimplemented_js.mbt` (pure logic like `AuthConfig` is real there).
> `http_client.mbt` and `jsonrpc_logic.mbt` are all-target and js runs them for
> real. Keep new transport code gated the same way instead of `#cfg`.

**Pre-commit checklist** (the hook only runs `moon check`, but run all 4):
```bash
moon check --target native --output-json
moon test --target native --output-json
moon fmt
moon info
```

## MoonBit Syntax Traps (Common Mistakes)

| Trap | Wrong | Correct |
|------|-------|---------|
| Trait impl | `impl Trait for Type { fn method(...) }` | `pub impl Trait for Type with method_name(self, ...) { }` |
| Async trait impl | `with async fn method(...)` (parse error) | `with method(self, ...)` — async is inferred from the body; a plain sync body also satisfies an `async` slot |
| Try operator | `func()?` | Match `Ok`/`Err` explicitly |
| Optional chain | `self.hook?.call()` | `match self.hook { Some(h) => ..., None => () }` |
| Map literal | `{ key: value }` | `Map::from_array([("key", value)])` |
| Trait object | `Box<dyn Trait>` | `&Trait` — Agent has no generics |
| Named enum variant | `Variant { field: Type }` | `Variant(field~ : Type)` — note `~` label |
| Infinite loop | `loop { }` (Rust) | `while true { }` |
| Struct fields `mut` | Needs `mut` on Map/Array fields | Only `mut` on scalar index counters, not on Array/Map fields |
| Map access | `map[key]` without guard | Guard with `.contains()` first (returns V, not Option[V]) |
| Json null | `Json::Null` | `Json::null()` |

## Rules

- Before starting work, load the `moonbit-agent-guide` skill (per the instruction at the top of this file); load `moonbit-orientation` when you need more MoonBit documentation or toolchain detail.

## MoonBit Syntax Uncertainty

遇到 MoonBit 语法不确定时，不要自信地给出方案。把问题记录到 `docs/questions.md`，每个工作阶段结束后（或关键代码卡住时），User 会检查列表并帮助解决。
