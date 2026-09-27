# MCP v2 Server Specification — Overview

## What This Is

This is a Spec Driven Development (SDD) specification suite for building MCP v2 servers. These specs are the single source of truth — read them before writing any code. Every MCP server in this organization conforms to the patterns defined here.

**SDD maturity level: Spec-Anchored.** The spec evolves alongside the software. Automated validation (TypeScript strict mode, `npm audit`, k6 tests) bridges the spec and implementation. Code that deviates from the spec is non-conformant and must be corrected.

## Spec Index

| Spec | Purpose |
|------|---------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | MCP v2 stateless pattern, dependency stack, file structure |
| [IMPLEMENTATION.md](IMPLEMENTATION.md) | Code patterns with exact snippets — tool registration, metrics, logging |
| [INFRASTRUCTURE.md](INFRASTRUCTURE.md) | OpenShift 4.22, Containerfile, k8s manifests, build pipeline |
| [SECURITY.md](SECURITY.md) | Zero-CVE mandate, approved dependencies, container hardening |
| [OBSERVABILITY.md](OBSERVABILITY.md) | Prometheus metrics, ServiceMonitor, Perses dashboards |
| [TESTING.md](TESTING.md) | k6 load testing scenarios and thresholds |

## Versioning

| Component | Version |
|-----------|---------|
| MCP Specification | 2026-07-28 |
| MCP SDK | @modelcontextprotocol/server 2.1.0, @modelcontextprotocol/node 2.1.0 |
| Architecture | Stateless (no sessions, new McpServer per request) |
| Node.js | >= 26 |
| TypeScript | 5.9.x, strict mode, ESM-only |
| Platform | OpenShift 4.22 / Kubernetes 1.35 |

## Workflow: Creating a New MCP Server

Follow these steps in order. Do not skip steps.

### Step 1: Scaffold from Template

```bash
# Copy the template to a new project directory
cp -r mcp-v2-template/ ~/dev/<your-server-name>
cd ~/dev/<your-server-name>

# Initialize git
git init
```

### Step 2: Rename the Server

The template ships as a working `mcp-hello-world` server. Rename it to your server by searching and replacing these values across the entire project:

| Find | Replace With | Example |
|------|-------------|---------|
| `mcp-hello-world` | Your server's kebab-case name | `weather-mcp` |
| `Hello world MCP v2 server` | One-line description | `MCP server for weather data` |
| `MCP Hello World` | Human-readable display name | `Weather MCP` |
| `https://github.com/your-org/mcp-hello-world.git` | Your GitHub repo HTTPS URL | `https://github.com/org/weather-mcp.git` |

Files that need renaming:
- `package.json` — name, description
- `src/server.ts` — service name in health/ready responses, McpServer name
- `src/metrics.ts` — server name in `mcp_server_info` gauge
- `k8s/deployment.yaml` — all resource names, labels, container name, image trigger
- `k8s/service.yaml` — name, labels, selector
- `k8s/route.yaml` — name, labels, service reference
- `k8s/imagestream.yaml` — name, labels
- `k8s/buildconfig.yaml` — name, labels, output, git URI
- `k8s/servicemonitor.yaml` — name, labels, selector
- `k8s/dashboard.yaml` — name, display name, all PromQL `job=` labels
- `k6/load-test.js` — route comment, tool payloads (replace hello tool with your tools)

### Step 3: Install Dependencies

```bash
npm install
```

Verify zero CVEs immediately:

```bash
npm audit
```

If any critical or high vulnerabilities are reported, resolve them before proceeding. See [SECURITY.md](SECURITY.md).

### Step 4: Implement Your Tools

Edit `src/server.ts`. Remove the example `hello` tool and register your own tools following the pattern in [IMPLEMENTATION.md](IMPLEMENTATION.md):

```typescript
server.registerTool('your-tool-name', {
  description: 'What this tool does',
  inputSchema: {
    param1: z.string().describe('Parameter description'),
    param2: z.number().optional().describe('Optional parameter'),
  },
}, withMetrics('your-tool-name', async ({ param1, param2 }) => {
  try {
    const result = await yourFunction(param1, param2);
    return toolResult(result);
  } catch (error) {
    log('error', 'tool_error', { tool: 'your-tool-name', error: String(error) });
    return toolError(error);
  }
}));
```

For servers with many tools, extract handlers into `src/tools/` — see IMPLEMENTATION.md for the pattern.

### Step 5: Build and Test Locally

```bash
npm run build          # Must produce zero TypeScript errors
```

Run the conformance validation script (20 automated checks):

```bash
bash validate.sh
```

This checks: TypeScript compilation, zero CVEs, file structure (Containerfile, k8s manifests, k6 tests), security (no prohibited deps, no eval/exec, security context in deployment), and endpoint verification (health, ready, metrics, MCP tool call). All 20 checks must pass.

If you need to test manually:

```bash
npm start              # Starts on port 8080

# Health and readiness
curl http://localhost:8080/health
curl http://localhost:8080/ready

# Prometheus metrics
curl http://localhost:8080/metrics

# MCP tool call
curl -X POST http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"your-tool-name","arguments":{"param1":"test"}}}'
```

### Step 6: Write k6 Load Tests

Edit `k6/load-test.js`. Replace the example tool payloads with your tools. See [TESTING.md](TESTING.md) for the full pattern.

### Step 7: Create GitHub Repository

```bash
gh repo create org/<your-server-name> --private --source=. --push
```

### Step 8: Deploy to OpenShift

Create the OCP resources in your target namespace:

```bash
# Set your namespace
NAMESPACE=<your-namespace>

# Create ImageStream and BuildConfig (triggers first build)
oc apply -f k8s/imagestream.yaml -n $NAMESPACE
oc apply -f k8s/buildconfig.yaml -n $NAMESPACE

# Wait for the build to complete
oc logs -f bc/<your-server-name> -n $NAMESPACE

# Deploy the application
oc apply -f k8s/deployment.yaml -n $NAMESPACE
oc apply -f k8s/service.yaml -n $NAMESPACE
oc apply -f k8s/route.yaml -n $NAMESPACE

# Enable Prometheus scraping
oc apply -f k8s/servicemonitor.yaml -n $NAMESPACE

# Deploy the Perses dashboard (different namespace)
oc apply -f k8s/dashboard.yaml -n openshift-cluster-observability-operator
```

### Step 9: Verify Deployment

```bash
# Check pod is running
oc get pods -l app=<your-server-name> -n $NAMESPACE

# Check route
ROUTE=$(oc get route <your-server-name> -n $NAMESPACE -o jsonpath='{.spec.host}')

# Test endpoints through the route
curl https://$ROUTE/health
curl https://$ROUTE/ready

# Test MCP tool call
curl -X POST https://$ROUTE/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"your-tool-name","arguments":{"param1":"test"}}}'

# Verify Prometheus target is UP (check OCP console → Observe → Targets)

# Run k6 load tests against the route
k6 run --env BASE_URL=https://$ROUTE k6/load-test.js
```

### Step 10: Commit and Iterate

```bash
git add -A
git commit -m "Initial MCP v2 server implementation"
git push origin main
```

Start the next build if BuildConfig doesn't have a webhook trigger:

```bash
oc start-build <your-server-name> -n $NAMESPACE
```

## Directory Layout

```
sdd_demo/
├── .clinerules              # Cline agent rules (read first)
├── spec/                    # Specification suite (this directory)
│   ├── OVERVIEW.md          # You are here
│   ├── ARCHITECTURE.md      # MCP v2 pattern and dependency stack
│   ├── IMPLEMENTATION.md    # Code patterns and snippets
│   ├── INFRASTRUCTURE.md    # OpenShift, Containerfile, k8s manifests
│   ├── SECURITY.md          # Zero-CVE mandate, approved dependencies
│   ├── OBSERVABILITY.md     # Metrics, ServiceMonitor, dashboards
│   └── TESTING.md           # k6 load testing
└── mcp-v2-template/         # Reference implementation (copy to start)
    ├── Containerfile
    ├── validate.sh          # Conformance validation (20 checks)
    ├── package.json
    ├── tsconfig.json
    ├── src/
    │   ├── server.ts
    │   └── metrics.ts
    ├── k8s/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── route.yaml
    │   ├── imagestream.yaml
    │   ├── buildconfig.yaml
    │   ├── servicemonitor.yaml
    │   └── dashboard.yaml
    └── k6/
        └── load-test.js
```
