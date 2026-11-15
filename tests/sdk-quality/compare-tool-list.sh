#!/usr/bin/env bash
# Same-run ABBA comparison for 256-tool tools/list responses.
set -euo pipefail
mkdir -p artifacts/list-ab
server_pid=""

stop_server() {
  if [ -n "$server_pid" ]; then
    kill -TERM -- "-$server_pid" 2>/dev/null || true
    sleep 0.2
    kill -KILL -- "-$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    server_pid=""
  fi
}
trap stop_server EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

{
  uname -a
  lscpu
  moon version --all
  node --version
  git -C base rev-parse HEAD
  git -C candidate rev-parse HEAD
} > artifacts/list-ab/environment.txt 2>&1

index=0
for side in base candidate candidate base; do
  index=$((index + 1))
  echo "=== tool list ABBA slot $index: $side ==="
  (
    cd "$side"
    exec setsid ./_build/native/release/build/colmugx/mcp/conformance/server/server.exe
  ) > "artifacts/list-ab/server-$index-$side.log" 2>&1 &
  server_pid=$!
  ready=0
  for _ in $(seq 1 120); do
    if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
    status=$(curl --max-time 1 -sS -o /dev/null -w '%{http_code}' \
      http://127.0.0.1:3000/mcp 2>/dev/null || true)
    if [ -n "$status" ] && [ "$status" != "000" ]; then ready=1; break; fi
    sleep 0.25
  done
  if [ "$ready" -ne 1 ]; then
    cat "artifacts/list-ab/server-$index-$side.log"
    exit 1
  fi
  for concurrent in 1 8; do
    timeout --signal=TERM --kill-after=3s 30s \
      node tests/sdk-quality/list-load.cjs "$concurrent" 6 \
      > "artifacts/list-ab/slot-$index-$side-c$concurrent.json" \
      2> "artifacts/list-ab/slot-$index-$side-c$concurrent.stderr"
    cat "artifacts/list-ab/slot-$index-$side-c$concurrent.json"
  done
  stop_server
  sleep 0.5
done

node <<'NODE'
const fs = require('fs');
const labels = ['base', 'candidate', 'candidate', 'base'];
const rows = [];
for (let i = 0; i < labels.length; i++) {
  for (const concurrency of [1, 8]) {
    const side = labels[i];
    const path = 'artifacts/list-ab/slot-' + (i + 1) + '-' + side + '-c' + concurrency + '.json';
    const record = JSON.parse(fs.readFileSync(path, 'utf8'));
    if (record.failures || record.successes < 1) throw new Error('Failed/empty results in ' + path);
    rows.push({ slot: i + 1, side, concurrency, ...record });
  }
}
const mean = (side, concurrency) => {
  const values = rows.filter(r => r.side === side && r.concurrency === concurrency).map(r => r.rps);
  return values.reduce((a,b) => a + b, 0) / values.length;
};
const lines = [
  '## Same-run ABBA: 256-tool tools/list',
  '',
  '| Slot | Revision | Concurrency | Requests/s | p95 (ms) | Errors |',
  '|---|---|---:|---:|---:|---:|',
  ...rows.map(r => '| ' + r.slot + ' | ' + r.side + ' | ' + r.concurrency + ' | ' + r.rps.toFixed(1) + ' | ' + r.p95Ms.toFixed(2) + ' | ' + r.failures + ' |'),
  '',
];
for (const concurrency of [1,8]) {
  const base = mean('base',concurrency);
  const candidate = mean('candidate',concurrency);
  lines.push('**Concurrency ' + concurrency + ':** baseline ' + base.toFixed(1) + ' req/s, candidate ' + candidate.toFixed(1) + ' req/s, delta ' + ((candidate/base-1)*100).toFixed(2) + '%');
  lines.push('');
}
lines.push('_Same GitHub Actions runner, ABBA order, two trials per revision; not a hardware-normalized comparison._');
const summary = lines.join('\n') + '\n';
fs.writeFileSync('artifacts/list-ab/summary.md', summary);
fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
console.log(summary);
NODE