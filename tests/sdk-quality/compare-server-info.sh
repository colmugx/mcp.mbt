#!/usr/bin/env bash
# Temporary A/B driver: run baseline vs candidate on the same Actions runner.
set -euo pipefail
mkdir -p artifacts/ab
server_pid=""

stop_server() {
  timeout --signal=KILL 5s mcpdo daemon stop >/dev/null 2>&1 || true
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
  echo "=== Toolchain ==="
  moon version --all
  node --version
  npm list --global @modelcontextprotocol/inspector
  uname -a
  lscpu
  echo "=== Revision ==="
  git -C base rev-parse HEAD
  git -C candidate rev-parse HEAD
} > artifacts/ab/environment.txt 2>&1

index=0
for side in base candidate candidate base; do
  index=$((index + 1))
  echo "=== A/B slot $index: $side ==="
  (cd "$side" && exec setsid ./_build/native/release/build/colmugx/mcp/conformance/server/server.exe) \
    > "artifacts/ab/server-$index-$side.log" 2>&1 &
  server_pid=$!

  ready=0
  for _ in $(seq 1 100); do
    if ! kill -0 "$server_pid" 2>/dev/null; then
      break
    fi
    status=$(curl --max-time 1 -sS -o /dev/null -w '%{http_code}' \
      http://127.0.0.1:3000/mcp 2>/dev/null || true)
    if [ -n "$status" ] && [ "$status" != "000" ]; then
      ready=1
      break
    fi
    sleep 0.3
  done
  if [ "$ready" != 1 ]; then
    cat "artifacts/ab/server-$index-$side.log"
    echo "Server failed to start: $side"
    exit 1
  fi

  timeout --signal=TERM --kill-after=3s 20s mcpdo connect \
    http://127.0.0.1:3000/mcp --era auto \
    > "artifacts/ab/connect-$index-$side.log" 2>&1

  timeout --signal=TERM --kill-after=3s 70s \
    mcpdo --format json --connection http://127.0.0.1:3000/mcp \
    tools/call bench_echo message:=benchmark \
    --load --load-steps 1,4,16,64 \
    --load-step-duration 5 --load-interval 2 \
    --load-max-error-rate 0.01 \
    > "artifacts/ab/result-$index-$side.json" \
    2> "artifacts/ab/result-$index-$side.stderr"

  echo "=== A/B slot $index complete ==="
  stop_server
  sleep 0.5
done

node <<'NODE'
const fs = require('fs');
const labels = ['base','candidate','candidate','base'];
const data = labels.map((label, i) => {
  const d = JSON.parse(fs.readFileSync('artifacts/ab/result-'+(i+1)+'-'+label+'.json','utf8'));
  if (d.errors || d.toolErrors || d.errorRate) throw new Error('Load errors in slot '+(i+1));
  return {slot:i+1,ref:label,throughput:d.throughput,p95:d.latencyMs.p95,requests:d.requests,errors:d.errors};
});
const avg = (label, key) => {
  const values = data.filter(x => x.ref===label).map(x=>x[key]);
  return values.reduce((a,b)=>a+b,0)/values.length;
};
const base=avg('base','throughput'), candidate=avg('candidate','throughput');
const delta=(candidate/base-1)*100;
const summary=[
  '## Same-run A/B: serverInfo cache (ABBA)',
  '',
  '| Slot | Commit | Throughput (req/s) | p95 (ms) | Requests | Errors |',
  '|---|---|---:|---:|---:|---:|',
  ...data.map(x=>['|',x.slot,'|',x.ref,'|',x.throughput,'|',x.p95,'|',x.requests,'|',x.errors,'|'].join(' ')),
  '',
  'Mean throughput, base: '+base.toFixed(1)+' req/s',
  '',
  'Mean throughput, candidate: '+candidate.toFixed(1)+' req/s',
  '',
  'Observed delta: '+delta.toFixed(2)+'%',
  '',
  '_One runner, two repetitions each; still insufficient to claim a stable win without corroboration._',
].join('\n');
fs.writeFileSync('artifacts/ab/summary.md', summary+'\n');
fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,summary+'\n');
console.log(summary);
NODE