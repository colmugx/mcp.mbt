#!/usr/bin/env bash
# Same-run ABBA measurement for modern MCPClient -> unchanged MCPServer.
# Both clients use identical benchmark source, identical native compiler, same
# server and same runner; only the SDK revision differs.
set -euo pipefail
mkdir -p artifacts/client-ab
server_pid=""

cleanup() {
  if [ -n "$server_pid" ]; then
    kill -TERM -- "-$server_pid" 2>/dev/null || true
    sleep 0.2
    kill -KILL -- "-$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    server_pid=""
  fi
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

{
  uname -a
  lscpu
  moon version --all
  git -C base rev-parse HEAD
  git -C candidate rev-parse HEAD
} > artifacts/client-ab/environment.txt 2>&1

# A single baseline server is kept up through the four trials: only the
# MCPClient version changes; the server implementation stays fixed.
setsid ./base/_build/native/release/build/colmugx/mcp/conformance/server/server.exe \
  > artifacts/client-ab/server.log 2>&1 &
server_pid=$!

ready=0
for _ in $(seq 1 120); do
  if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
  status=$(curl --max-time 1 -sS -o /dev/null -w '%{http_code}' \
    http://127.0.0.1:3000/mcp 2>/dev/null || true)
  if [ -n "$status" ] && [ "$status" != "000" ]; then
    ready=1
    break
  fi
  sleep 0.25
done
if [ "$ready" -ne 1 ]; then
  cat artifacts/client-ab/server.log
  echo "Server failed to start."
  exit 1
fi

index=0
for side in base candidate candidate base; do
  index=$((index + 1))
  echo "=== MRTR client ABBA slot $index: $side ==="
  timeout --signal=TERM --kill-after=5s 180s \
    "./$side/_build/native/release/build/colmugx/mcp/conformance/client_benchmark/client_benchmark.exe" \
    > "artifacts/client-ab/slot-$index-$side.jsonl" \
    2> "artifacts/client-ab/slot-$index-$side.stderr"
  cat "artifacts/client-ab/slot-$index-$side.jsonl"
  sleep 1
done

node <<'NODE'
const fs = require('node:fs');
const labels = ['base', 'candidate', 'candidate', 'base'];
const slots = labels.map((side, i) => {
  const path = 'artifacts/client-ab/slot-' + (i + 1) + '-' + side + '.jsonl';
  const records = fs.readFileSync(path, 'utf8').trim().split(/\r?\n/)
    .filter(line => line.startsWith('{"concurrency"')).map(JSON.parse);
  for (const c of [1, 4, 16, 64]) {
    const row = records.find(x => x.concurrency === c);
    if (!row || row.requests !== 150 * c || row.errors !== 0 || row.throughput_rps <= 0) {
      throw new Error('Incomplete/failed ' + path + ' at concurrency ' + c);
    }
  }
  return {slot: i+1, side, rows: records};
});
const average = (side, concurrency) => {
  const rows = slots.filter(x=>x.side===side).map(x=>
    x.rows.find(y=>y.concurrency===concurrency).throughput_rps);
  return rows.reduce((a,b)=>a+b,0) / rows.length;
};
const lines = [
  '## Same-run ABBA: MCPClient MRTR tools/call',
  '',
  'Unchanged main server, same MoonBit compiler/runner, 150 tool calls per worker.',
  '',
  '| Slot | Revision | Concurrency | Requests/s | Errors |',
  '|---|---|---:|---:|---:|',
  ...slots.flatMap(s=>s.rows.map(r=>
    '| '+s.slot+' | '+s.side+' | '+r.concurrency+' | '+r.throughput_rps.toFixed(1)+' | '+r.errors+' |')),
  '',
];
for (const concurrency of [1,4,16,64]) {
  const base=average('base',concurrency), candidate=average('candidate',concurrency);
  lines.push('**Concurrency '+concurrency+':** baseline '+base.toFixed(1)+
    ' req/s, candidate '+candidate.toFixed(1)+
    ' req/s, delta '+((candidate/base-1)*100).toFixed(2)+'%');
  lines.push('');
}
lines.push('_Two trials per revision, ABBA order. A small delta needs repeat runs to establish significance._');
const summary=lines.join('\n')+'\n';
fs.writeFileSync('artifacts/client-ab/summary.md',summary);
fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,summary);
console.log(summary);
NODE
