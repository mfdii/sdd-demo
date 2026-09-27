# MCP v2 Server Architecture

## MCP Protocol Version

MCP 2026-07-28 specification. Stateless architecture — no sessions, no session IDs, no connection state. Every HTTP request is independent.

## Stateless Server Pattern

The server uses the MCP SDK v2 factory pattern. A new `McpServer` instance is created for every incoming request. There is no shared state between requests.

```
HTTP POST /mcp
  → Express receives request
  → toNodeHandler(handler) delegates to MCP handler
  → createMcpHandler calls the factory function
  → Factory creates a fresh McpServer with registered tools
  → McpServer processes the JSON-RPC request
  → Tool callback executes
  → Response returned as SSE (event: message\ndata: {...})
```

The factory function is called once per request:

```typescript
const handler = createMcpHandler(() => {
  const server = new McpServer(
    { name: 'your-app-name', version: '2.0.0' },
    { capabilities: { tools: {} } },
  );

  // Register all tools here
  server.registerTool('tool-name', { ... }, handler);

  return server;
});
```

## HTTP Layer

Express 5.x serves as the HTTP layer. Every server exposes exactly 4 endpoints:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Liveness probe — returns `{"status":"ok","service":"<name>"}` |
| `/ready` | GET | Readiness probe — returns `{"status":"ready","service":"<name>"}` |
| `/metrics` | GET | Prometheus metrics in text exposition format |
| `/mcp` | ALL | MCP JSON-RPC endpoint (POST for tool calls, GET for SSE) |

Endpoint registration order matters. Register in this exact order:

1. `app.use(httpMetrics)` — before all routes
2. `app.get('/health', ...)` 
3. `app.get('/ready', ...)`
4. `app.get('/metrics', ...)`
5. `app.all('/mcp', ...)`

## MCP Request Format

Clients send JSON-RPC 2.0 requests with two required headers:

```
Content-Type: application/json
Accept: application/json, text/event-stream
```

Request body:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "tool-name",
    "arguments": { "param1": "value" }
  }
}
```

Responses are SSE-formatted:

```
event: message
data: {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"..."}]}}
```

The `Accept` header is mandatory. Omitting it returns `406 Not Acceptable`.

## Dependency Stack

These are the only framework-level dependencies. All versions are locked.

| Package | Version | Purpose |
|---------|---------|---------|
| `@modelcontextprotocol/server` | 2.1.0 | MCP server SDK (createMcpHandler, McpServer) |
| `@modelcontextprotocol/node` | 2.1.0 | Node.js HTTP adapter (toNodeHandler) |
| `express` | 5.2.1 | HTTP framework |
| `prom-client` | 15.1.3 | Prometheus metrics |
| `zod` | 4.6.5 | Input schema validation |

Dev dependencies:

| Package | Version | Purpose |
|---------|---------|---------|
| `typescript` | 5.9.3 | TypeScript compiler |
| `@types/express` | ^5.0.0 | Express type definitions |
| `@types/node` | ^22.10.2 | Node.js type definitions |

Do not add alternative frameworks (Fastify, Hono, Koa). Do not add utility libraries (lodash, ramda) — use native JS/TS.

## TypeScript Configuration

- Target: ES2022
- Module: Node16
- Module resolution: Node16
- Strict mode: enabled
- ESM only: `"type": "module"` in package.json
- All imports use `.js` extension: `import { foo } from './bar.js'`
- Output directory: `dist/`
- Source directory: `src/`

## File Structure

Minimal server (1-10 tools):

```
project/
├── Containerfile
├── package.json
├── tsconfig.json
├── src/
│   ├── server.ts          # Entry point: MCP handler + Express app + tool registration
│   └── metrics.ts         # Prometheus instrumentation
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

Larger server (10+ tools):

```
project/
├── src/
│   ├── server.ts          # MCP handler + Express app (imports tool handlers)
│   ├── metrics.ts         # Prometheus instrumentation
│   └── tools/
│       ├── index.ts       # Re-exports all handlers
│       ├── toolOne.ts     # Individual tool handler + schema
│       └── toolTwo.ts
```

## Tool Response Helpers

Every server defines these two helpers:

```typescript
function toolResult(result: unknown) {
  return { content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }] };
}

function toolError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return {
    content: [{ type: 'text' as const, text: JSON.stringify({ error: message }, null, 2) }],
    isError: true as const,
  };
}
```

`toolResult()` wraps successful output. `toolError()` wraps errors with `isError: true` so the metrics wrapper can detect failures.

## Logging

Structured JSON to stderr. Never use `console.log` (stdout interferes with MCP stdio transports in other contexts).

```typescript
function log(level: string, event: string, data: Record<string, unknown> = {}) {
  process.stderr.write(
    JSON.stringify({ timestamp: new Date().toISOString(), level, event, ...data }) + '\n'
  );
}
```

## Graceful Shutdown

Every server handles SIGTERM for clean pod termination:

```typescript
process.on('SIGTERM', async () => {
  log('info', 'shutdown_initiated');
  await handler.close();
  // Close any other resources (DB pools, etc.)
  process.exit(0);
});
```

## Runtime

- Node.js >= 26 (engine constraint in package.json)
- Port: 8080 (configurable via `PORT` env var)
- `NODE_ENV=production` in container
