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
| [ENVIRONMENT.md](ENVIRONMENT.md) | Dev environment, shell commands, file editing strategy |

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

### Step 1: Scaffold and Rename

```bash
# Copy the template to a new project directory
cp -r mcp-v2-template/ <your-server-name>
cd <your-server-name>

# Rename all references (handles all files, excludes node_modules/dist/.git)
bash rename.sh <your-server-name> '<your description>'
# Example: bash rename.sh mcp-weather 'MCP server for weather data'
```

The `rename.sh` script replaces `mcp-hello-world` in all source, config, and k8s files. It also updates the description and display name. **Always use this script — do not manually find-and-replace.**

After renaming, reinstall dependencies (the old package-lock.json references the old name):

```bash
rm -rf node_modules package-lock.json
npm install
```

Verify zero CVEs immediately:

```bash
npm audit
```

If any critical or high vulnerabilities are reported, resolve them before proceeding. See [SECURITY.md](SECURITY.md).

### Step 2: Implement Your Tools

Edit `src/server.ts`. **Rewrite the entire file** — do not try to patch it. Keep all the imports, helpers (`log`, `toolResult`, `toolError`), Express app setup, and SIGTERM handler. Replace only the `hello` tool registration with your own tools following the pattern in [IMPLEMENTATION.md](IMPLEMENTATION.md). See [ENVIRONMENT.md](ENVIRONMENT.md) for the recommended file editing strategy.

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

### Step 3: Build and Validate

```bash
npm run build          # Must produce zero TypeScript errors
```

Run the conformance validation script (20 automated checks):

```bash
bash validate.sh
```

This checks: TypeScript compilation, zero CVEs, file structure, security, customization (hello tool removed, app renamed), and endpoint verification. All checks must pass. If any fail, fix the issue and re-run `bash validate.sh`.

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

### Step 4: Write k6 Load Tests

Edit `k6/load-test.js`. Replace the example tool payloads with your tools. See [TESTING.md](TESTING.md) for the full pattern.

### Step 5: Create GitHub Repository

```bash
gh repo create org/<your-server-name> --private --source=. --push
```

### Step 6: Deploy to OpenShift

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

### Step 7: Verify Deployment

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

### Step 8: Commit and Iterate

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
│   ├── TESTING.md           # k6 load testing
│   └── ENVIRONMENT.md       # Dev environment, shell, file editing
└── mcp-v2-template/         # Reference implementation (copy to start)
    ├── Containerfile
    ├── rename.sh            # Renames template to your app (run first)
    ├── validate.sh          # Conformance validation (26 checks)
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
