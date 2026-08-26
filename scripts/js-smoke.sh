#!/usr/bin/env bash
# js-smoke.sh — Phase 2 JS-target smoke test for HttpClientTransport.
#
# Verifies, against this repository's working tree, that:
#   1. POST + single JSON response round-trips on the js target (node),
#      both at the raw-transport level and through MCPClient
#      (server/discover probe -> tools/list -> tools/call).
#   2. POST answered with text/event-stream delivers events to
#      HttpClientTransport::receive incrementally (not buffered to EOF).
#   3. The real MCP server flushes subscriptions/listen SSE: the ack event
#      must reach curl while the stream is still open (headers + events on
#      the wire immediately, not buffered until end_response).
#
# How it runs:
#   - Builds two native counterparts from the working tree via temporary
#     main packages materialized under src/js_smoke_tmp/:
#       * 127.0.0.1:4240/mcp — real MCP server (mcp_server + HttpTransport)
#       * 127.0.0.1:4241/sse — raw SSE emitter (3 events, 700ms apart, EOF)
#   - Runs the js-target client against both.
#
# Why temporary packages instead of `moon run -e`: scratch snippets resolve
# `colmugx/mcp` from the published registry copy, NOT the working tree, so
# they cannot test local changes.
#
# Success = client output contains "SMOKE RESULT: PASS". The js async runtime
# exits 0 even on unhandled errors, so the marker (not the exit code alone)
# is authoritative.
#
# Requires: moon on PATH, node >= 18 on PATH, free ports 4240/4241.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_PKG_DIR="$REPO_ROOT/src/js_smoke_tmp"
WORK_DIR="$(mktemp -d /tmp/mcp-js-smoke.XXXXXX)"
MCP_PORT=4240
SSE_PORT=4241
MCP_PID=""
SSE_PID=""

cleanup() {
  local exit_code=$?
  # `moon run` wraps the built executable as a child process, and neither
  # reliably dies on SIGTERM, so kill children first, then the wrapper, then
  # sweep by the unique temp-package path. No `wait`: the wrappers can linger.
  local pid
  for pid in $MCP_PID $SSE_PID; do
    [ -n "$pid" ] || continue
    pkill -TERM -P "$pid" 2>/dev/null
    kill -TERM "$pid" 2>/dev/null
  done
  sleep 1
  pkill -TERM -f "js_smoke_tmp" 2>/dev/null
  sleep 0.5
  pkill -KILL -f "js_smoke_tmp" 2>/dev/null
  rm -rf "$TMP_PKG_DIR"
  rm -rf "$WORK_DIR"
  exit $exit_code
}
trap cleanup EXIT INT TERM

fail() {
  echo "js-smoke: FAIL — $*" >&2
  exit 1
}

wait_for_port() {
  # wait_for_port <port> <name> <timeout_seconds>
  local port=$1 name=$2 timeout=$3 i
  for ((i = 0; i < timeout * 2; i++)); do
    if lsof -i :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "js-smoke: $name listening on $port"
      return 0
    fi
    sleep 0.5
  done
  echo "js-smoke: $name log:" >&2
  cat "$WORK_DIR/$name.log" >&2 2>/dev/null
  fail "$name did not start within ${timeout}s"
}

command -v moon >/dev/null 2>&1 || fail "moon not found on PATH"
command -v node >/dev/null 2>&1 || fail "node not found on PATH"
command -v lsof >/dev/null 2>&1 || fail "lsof not found on PATH"
command -v curl >/dev/null 2>&1 || fail "curl not found on PATH"

for port in "$MCP_PORT" "$SSE_PORT"; do
  if lsof -i :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    fail "port $port already in use"
  fi
done

# --- 1. Materialize temporary main packages from the working tree ----------

mkdir -p "$TMP_PKG_DIR/mcp_server_main" "$TMP_PKG_DIR/sse_server_main" "$TMP_PKG_DIR/client_main"

cat > "$TMP_PKG_DIR/mcp_server_main/moon.pkg" <<'EOF'
import {
  "colmugx/mcp",
  "moonbitlang/async",
  "moonbitlang/core/json",
}

pkgtype(kind: "executable")
EOF

cat > "$TMP_PKG_DIR/mcp_server_main/main.mbt" <<'EOF'
///|
/// js-smoke counterpart: native MCP HTTP server with one echo tool.
async fn main {
  let schema = @json.parse(
    "{\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\"}},\"required\":[\"text\"]}",
  )
  @mcp.mcp_server(name="js-smoke-server", version="1.2.3")
    .tool(
      "echo",
      "Echo back text",
      schema,
      fn(args) {
        let text = if args is Object(o) {
          match o.get("text") {
            Some(String(s)) => s
            _ => ""
          }
        } else {
          ""
        }
        Ok(@mcp.ToolResult::text("Echo: " + text))
      },
    )
    .run_http(port=4240)
}
EOF

cat > "$TMP_PKG_DIR/sse_server_main/moon.pkg" <<'EOF'
import {
  "moonbitlang/async",
  "moonbitlang/async/http",
  "moonbitlang/async/socket",
}

pkgtype(kind: "executable")
EOF

cat > "$TMP_PKG_DIR/sse_server_main/main.mbt" <<'EOF'
///|
/// js-smoke counterpart: raw SSE emitter. Answers every POST with an
/// event-stream of three JSON events spaced 700ms apart, then EOF —
/// deterministic input for judging incremental delivery on the js client.
async fn main {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:4241"), reuse_addr=true) catch {
    e => {
      println("SSE emitter failed to bind: " + e.to_string())
      return
    }
  }
  println("sse-emitter-ready")
  server.run_forever(async fn(_req, body, conn) {
    let _ = body.read_all()
    conn.send_response(
      200,
      "OK",
      extra_headers={
        "Content-Type": "text/event-stream",
        "X-Accel-Buffering": "no",
      },
    )
    for i in 1..=3 {
      conn.write("event: message\ndata: {\"n\":\{i}}\n\n")
      // ServerConnection writes are buffered; flush is what makes each event
      // hit the wire immediately (same rule the repository's HttpTransport
      // SSE branch follows).
      conn.flush()
      @async.sleep(700)
    }
    conn.end_response()
  })
}
EOF

cat > "$TMP_PKG_DIR/client_main/moon.pkg" <<'EOF'
import {
  "colmugx/mcp",
  "colmugx/mcp/transport",
  "moonbitlang/async",
  "moonbitlang/core/json",
}

pkgtype(kind: "executable")
EOF

cat > "$TMP_PKG_DIR/client_main/main.mbt" <<'EOF'
///|
/// js-target smoke client for HttpClientTransport. Runs against the two
/// native counterparts started by scripts/js-smoke.sh:
///   - 127.0.0.1:4240/mcp  — real MCP server (single-JSON responses)
///   - 127.0.0.1:4241/sse  — raw SSE emitter (3 events, 700ms apart, then EOF)
/// Any step failure raises at the end so the process exits non-zero.
///
/// Not probed here from js (the script probes it with curl instead):
///   - MCP-server `subscriptions/listen` SSE: timing out an in-flight send
///     kills the js process (send converts cancellation errors into
///     ReadError), so incremental delivery against the real server is
///     verified by the script's curl probe, not from js.
suberror SmokeFailure {
  SmokeFailure(String)
}

///|
/// One-line summary of a JSON-RPC response: id, serverInfo, tools count.
fn summarize(label : String, msg : String) -> String {
  let json = @json.parse(msg) catch { _ => return "\{label}: <not json> \{msg}" }
  if json is Object(o) {
    let id = match o.get("id") {
      Some(Number(n, ..)) => n.to_int().to_string()
      _ => "?"
    }
    if o.get("result") is Some(Object(r)) {
      let tools = match r.get("tools") {
        Some(Array(a)) => a.length().to_string()
        _ => "-"
      }
      let server_name = if r.get("_meta") is Some(Object(meta)) &&
        meta.get("io.modelcontextprotocol/serverInfo") is Some(Object(info)) {
        match info.get("name") {
          Some(String(n)) => n
          _ => "?"
        }
      } else {
        "-"
      }
      "\{label}: id=\{id} tools=\{tools} serverInfo=\{server_name}"
    } else {
      "\{label}: id=\{id} raw=\{msg}"
    }
  } else {
    "\{label}: raw=\{msg}"
  }
}

///|
async fn main {
  let mut failures = 0

  // [1] Raw transport: single-JSON POST round trip (tools/list).
  let raw = @transport.HttpClientTransport::HttpClientTransport(
    "http://127.0.0.1:4240/mcp",
  )
  let req = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}"
  match @async.with_timeout_opt(10000, async fn() {
    raw.send(req)
    raw.receive()
  }) {
    Some(Some(msg)) => println(summarize("[1] raw tools/list", msg))
    _ => {
      failures = failures + 1
      println("[1] raw tools/list FAILED (timeout/empty)")
    }
  }
  raw.close()

  // [2] Client layer: connect (server/discover probe) -> list_tools -> call_tool.
  match @async.with_timeout_opt(
      15000,
      async fn() {
        @mcp.MCPClient::connect_http(
          url="http://127.0.0.1:4240/mcp",
          name="js-smoke-client",
          version="0.1.0",
        )
      },
    ) {
    Some(Ok(client)) => {
      match @async.with_timeout_opt(10000, async fn() { client.list_tools() }) {
        Some(Ok(listing)) => {
          let first = if listing.tools.length() > 0 {
            listing.tools[0].name
          } else {
            "<none>"
          }
          println("[2] list_tools: count=\{listing.tools.length()} first=\{first}")
        }
        _ => {
          failures = failures + 1
          println("[2] list_tools FAILED")
        }
      }
      match @async.with_timeout_opt(
          10000,
          async fn() {
            client.call_tool("echo", arguments="{\"text\":\"hello-from-js\"}")
          },
        ) {
        Some(Ok(result)) => {
          let text = match result.content {
            [Text(t), ..] => t
            _ => "<no text content>"
          }
          println("[3] call_tool: isError=\{result.is_error} text=\{text}")
        }
        _ => {
          failures = failures + 1
          println("[3] call_tool FAILED")
        }
      }
      client.close()
    }
    Some(Err(e)) => {
      failures = failures + 1
      println("[2] connect_http FAILED: \{e.message()}")
    }
    None => {
      failures = failures + 1
      println("[2] connect_http FAILED: timeout")
    }
  }

  // [4] SSE incremental delivery vs raw emitter: send() drains in a background
  // task while receive() is timed; per-event arrival offsets prove whether
  // events surface as they arrive (~0/700/1400ms) or only at EOF (>=1400ms).
  let sse = @transport.HttpClientTransport::HttpClientTransport(
    "http://127.0.0.1:4241/sse",
  )
  let listen = "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"subscriptions/listen\",\"params\":{}}"
  let start = @async.now()
  @async.with_task_group(group => {
    group.spawn_bg(() => { sse.send(listen) catch { _ => () } })
    for i in 1..=3 {
      match @async.with_timeout_opt(8000, async fn() { sse.receive() }) {
        Some(Some(ev)) =>
          println("[4] sse event \{i} at +\{(@async.now() - start)}ms: \{ev}")
        _ => {
          failures = failures + 1
          println("[4] sse event \{i} FAILED (timeout/empty)")
        }
      }
    }
  })
  sse.close()

  println("SMOKE RESULT: \{if failures == 0 { "PASS" } else { "FAIL" }} (\{failures} failures)")
  if failures > 0 {
    raise SmokeFailure("\{failures} smoke step(s) failed")
  }
}
EOF

# --- 2. Start native counterparts ------------------------------------------

cd "$REPO_ROOT"
moon run --target native src/js_smoke_tmp/mcp_server_main >"$WORK_DIR/mcp_server.log" 2>&1 &
MCP_PID=$!
wait_for_port "$MCP_PORT" mcp_server 120

moon run --target native src/js_smoke_tmp/sse_server_main >"$WORK_DIR/sse_server.log" 2>&1 &
SSE_PID=$!
wait_for_port "$SSE_PORT" sse_server 120

# --- 3. Pre-flight curl probe (single-JSON path, server side) ---------------

curl -s -m 5 -X POST "http://127.0.0.1:$MCP_PORT/mcp" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2026-07-28' \
  -H 'Mcp-Method: tools/list' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  >"$WORK_DIR/curl_probe.json" || fail "curl probe against MCP server failed"
grep -q '"name":"echo"' "$WORK_DIR/curl_probe.json" \
  || fail "curl probe did not return the echo tool"

# --- 3b. Server-side SSE flush probe (subscriptions/listen) ------------------
# The stream stays open (no final response is ever sent), so any bytes curl
# collects before its own -m timeout prove the response headers and the ack
# event were flushed immediately rather than buffered until end_response.
# curl exits 28 on the timeout by design; only the collected bytes matter.

SSE_PROBE="$WORK_DIR/sse_probe.txt"
curl -s -m 3 -X POST "http://127.0.0.1:$MCP_PORT/mcp" \
  -H 'Content-Type: application/json' \
  -H 'Accept: text/event-stream' \
  -H 'MCP-Protocol-Version: 2026-07-28' \
  -H 'Mcp-Method: subscriptions/listen' \
  -d '{"jsonrpc":"2.0","id":9,"method":"subscriptions/listen","params":{}}' \
  >"$SSE_PROBE" || true
grep -q 'notifications/subscriptions/acknowledged' "$SSE_PROBE" \
  || fail "subscriptions/listen SSE ack not received within 3s (flush regression)"

# --- 4. Run the js client ----------------------------------------------------

echo "js-smoke: running js client (node $(node --version))"
moon run --target js src/js_smoke_tmp/client_main >"$WORK_DIR/client.log" 2>&1
CLIENT_EXIT=$?
cat "$WORK_DIR/client.log"

if ! grep -q 'SMOKE RESULT: PASS' "$WORK_DIR/client.log"; then
  fail "js client did not report PASS (exit=$CLIENT_EXIT, see output above)"
fi

if [ "$CLIENT_EXIT" -ne 0 ]; then
  fail "js client reported PASS but exited $CLIENT_EXIT"
fi

echo "js-smoke: PASS"
exit 0
