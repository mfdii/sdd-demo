# Testing Specification

## k6 Load Tests

Every MCP server includes a k6 load test at `k6/load-test.js`. Tests run locally against the deployed route.

### Prerequisites

```bash
# Install k6 (macOS)
brew install k6
```

### Test Script Structure

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

// Custom metrics
const toolSuccess = new Counter('mcp_tool_success');
const toolError = new Counter('mcp_tool_error');
const toolDuration = new Trend('mcp_tool_duration', true);

// BASE_URL is required — pass your OpenShift route
if (!__ENV.BASE_URL) {
  throw new Error('BASE_URL is required. Pass it via: k6 run --env BASE_URL=https://your-route.apps.cluster.example.com k6/load-test.js');
}
const BASE_URL = __ENV.BASE_URL;

// Required MCP headers
const MCP_HEADERS = {
  'Content-Type': 'application/json',
  Accept: 'application/json, text/event-stream',
};

// Define your tool payloads here
const tools = [
  { name: 'tool-one', args: { param: 'value' } },
  { name: 'tool-two', args: { param: 'other' } },
  // Add all your tools with representative arguments
];

function callTool(tool) {
  const payload = JSON.stringify({
    jsonrpc: '2.0',
    id: Math.floor(Math.random() * 1e6),
    method: 'tools/call',
    params: { name: tool.name, arguments: tool.args },
  });

  const res = http.post(`${BASE_URL}/mcp`, payload, {
    headers: MCP_HEADERS,
    tags: { tool: tool.name },
  });

  const ok = check(res, {
    'status 200': (r) => r.status === 200,
    'has result': (r) => r.body && r.body.includes('"result"'),
  });

  if (ok) toolSuccess.add(1, { tool: tool.name });
  else toolError.add(1, { tool: tool.name });
  toolDuration.add(res.timings.duration, { tool: tool.name });

  return ok;
}

// Scenario configuration
export const options = {
  scenarios: {
    populate: {
      executor: 'shared-iterations',
      vus: 2,
      iterations: tools.length * 3,
      maxDuration: '3m',
      exec: 'populate',
    },
    stress: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '30s', target: 5 },
        { duration: '1m', target: 10 },
        { duration: '30s', target: 20 },
        { duration: '1m', target: 20 },
        { duration: '30s', target: 0 },
      ],
      startTime: '3m30s',
      exec: 'stress',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.1'],
    mcp_tool_duration: ['p(95)<5000'],
  },
};

// Default function (required by k6)
export default function () {
  const tool = tools[Math.floor(Math.random() * tools.length)];
  callTool(tool);
  sleep(0.3);
}

// Populate: cycle through all tools systematically
export function populate() {
  const tool = tools[__ITER % tools.length];
  callTool(tool);
  sleep(0.5);
}

// Stress: random tools under increasing load
export function stress() {
  const tool = tools[Math.floor(Math.random() * tools.length)];
  callTool(tool);
  sleep(0.1);
}
```

### Scenarios

**Populate** — Warm up and verify all tools work. 2 VUs, each tool called 3 times, 0.5s between calls.

**Stress** — Ramp up concurrent users to find the breaking point:
- 0:00–0:30 → ramp to 5 VUs
- 0:30–1:30 → ramp to 10 VUs
- 1:30–2:00 → ramp to 20 VUs
- 2:00–3:00 → hold at 20 VUs
- 3:00–3:30 → ramp down to 0

The stress scenario starts at 3m30s to run after populate completes.

### Thresholds

| Threshold | Value | Meaning |
|-----------|-------|---------|
| `http_req_failed` | rate < 10% | Less than 10% of requests should fail |
| `mcp_tool_duration` | p95 < 5000ms | 95th percentile tool duration under 5 seconds |

Adjust thresholds based on your server's expected performance. ML-heavy servers may need higher duration thresholds.

### Tool Payload Rules

- Include every read-only tool with representative arguments
- Exclude mutation tools (create, update, delete) from stress scenarios — they may have side effects at scale
- Exclude heavy/expensive tools (RSS fetching, bulk processing) from stress scenarios
- Use realistic argument values that hit real code paths

### Running Tests

```bash
# BASE_URL is required — point it at your OpenShift route
k6 run --env BASE_URL=https://your-app.apps.cluster.example.com k6/load-test.js

# Populate only (verify tools work)
k6 run --env BASE_URL=https://your-app.apps.cluster.example.com k6/load-test.js --scenario populate

# With more detailed output
k6 run --env BASE_URL=https://your-app.apps.cluster.example.com k6/load-test.js --out json=results.json
```

### Interpreting Results

Key metrics to check:

```
✓ status 200          — all requests returned 200
✓ has result          — all responses contained a result

mcp_tool_duration     — tool execution time (watch p95)
http_req_failed       — error rate (should be < 10%)
http_req_duration     — full HTTP round-trip (includes network)
iterations            — total requests completed
vus_max               — peak concurrent users
```

If the stress test causes pod restarts (exit code 137 = OOM, exit code 139 = SIGSEGV):
- Increase memory limits in deployment.yaml
- For ML-heavy servers, add a concurrency semaphore around inference calls
- Reduce max VUs in the stress scenario

## Build Validation

Before committing, verify:

```bash
# 1. TypeScript compiles cleanly
npm run build

# 2. Zero CVEs
npm audit

# 3. Server starts
npm start &
sleep 2

# 4. Health check
curl -s http://localhost:8080/health | grep '"ok"'

# 5. Readiness check
curl -s http://localhost:8080/ready | grep '"ready"'

# 6. Metrics endpoint
curl -s http://localhost:8080/metrics | grep 'mcp_server_info'

# 7. MCP tool call (adjust tool name and args)
curl -s -X POST http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"hello","arguments":{"name":"test"}}}' \
  | grep '"result"'

# 8. Kill the server
kill %1
```

All 8 checks must pass before commit.
