// Minimal HTTP load driver for tools/list. Used identically against both SDK
// revisions in a single GitHub Actions runner. No dependencies beyond Node.
const http = require('node:http');
const { performance } = require('node:perf_hooks');
const concurrency = Number(process.argv[2] || 1);
const seconds = Number(process.argv[3] || 6);
const agent = new http.Agent({ keepAlive: true, maxSockets: 32 });
let nextId = 0;
let successes = 0;
let failures = 0;
const latency = [];
let responseBytes = 0;

function request(validate = false) {
  const body = JSON.stringify({
    jsonrpc: '2.0',
    id: ++nextId,
    method: 'tools/list',
    params: {
      _meta: {
        'io.modelcontextprotocol/protocolVersion': '2026-07-28',
        'io.modelcontextprotocol/clientCapabilities': {},
      },
    },
  });
  return new Promise((resolve, reject) => {
    const start = performance.now();
    const req = http.request({
      hostname: '127.0.0.1',
      port: 3000,
      path: '/mcp',
      method: 'POST',
      agent,
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json, text/event-stream',
        'MCP-Protocol-Version': '2026-07-28',
        'Mcp-Method': 'tools/list',
        'Content-Length': Buffer.byteLength(body),
      },
      timeout: 5000,
    }, res => {
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('error', reject);
      res.on('end', () => {
        const content = Buffer.concat(chunks);
        if (res.statusCode !== 200) {
          return reject(new Error('HTTP ' + res.statusCode + ': ' + content.toString('utf8').slice(0, 700)));
        }
        if (validate) {
          const txt = content.toString('utf8');
          const json = JSON.parse(txt);
          if (!json.result || !Array.isArray(json.result.tools) || json.result.tools.length !== 256) {
            return reject(new Error('Expected 256 tools: ' + txt.slice(0, 600)));
          }
        }
        resolve({ ms: performance.now() - start, bytes: content.length });
      });
    });
    req.on('timeout', () => req.destroy(new Error('HTTP request timeout')));
    req.on('error', reject);
    req.end(body);
  });
}

async function run() {
  // Validate the response schema before producing any throughput statistics.
  await request(true);
  const warmEnd = performance.now() + 750;
  async function warmWorker() {
    while (performance.now() < warmEnd) await request();
  }
  await Promise.all(Array.from({ length: concurrency }, warmWorker));
  const start = performance.now();
  const deadline = start + seconds * 1000;
  async function worker() {
    while (performance.now() < deadline) {
      try {
        const result = await request();
        latency.push(result.ms);
        responseBytes += result.bytes;
        successes++;
      } catch (e) {
        failures++;
        if (failures <= 3) console.error(String(e));
      }
    }
  }
  await Promise.all(Array.from({ length: concurrency }, worker));
  const elapsedMs = performance.now() - start;
  latency.sort((a, b) => a - b);
  const at = q => latency.length ? latency[Math.ceil(q * latency.length) - 1] : null;
  console.log(JSON.stringify({
    concurrency, seconds, successes, failures,
    elapsedMs, rps: successes * 1000 / elapsedMs,
    p50Ms: at(0.5), p95Ms: at(0.95), responseBytes,
  }));
  agent.destroy();
  if (failures > 0) process.exitCode = 1;
}
run().catch(err => { console.error(err); process.exitCode = 1; agent.destroy(); });
