# MCP v2 Server Implementation Guide

This document contains the exact code patterns to follow. Copy these patterns — do not invent alternatives.

## package.json

```json
{
  "name": "<your-app-name>",
  "version": "2.0.0",
  "description": "<one-line description>",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "start": "node dist/server.js",
    "dev": "tsc --watch & node --watch dist/server.js"
  },
  "dependencies": {
    "@modelcontextprotocol/node": "^2.1.0",
    "@modelcontextprotocol/server": "^2.0.3",
    "express": "^5.1.0",
    "prom-client": "^15.1.3",
    "zod": "^4.6.5"
  },
  "devDependencies": {
    "@types/express": "^5.0.0",
    "@types/node": "^22.10.2",
    "typescript": "^5.8.2"
  },
  "engines": {
    "node": ">=26.0.0"
  }
}
```

## tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist"]
}
```

## src/metrics.ts — Full Implementation

Copy this file exactly. Replace `{{APP_NAME}}` with your server name.

```typescript
import { Registry, Counter, Histogram, Gauge, collectDefaultMetrics } from 'prom-client';

const register = new Registry();

collectDefaultMetrics({ register });

new Gauge({
  name: 'mcp_server_info',
  help: 'MCP server identification',
  labelNames: ['name', 'version'] as const,
  registers: [register],
}).set({ name: '{{APP_NAME}}', version: '2.0.0' }, 1);

const toolCallsTotal = new Counter({
  name: 'mcp_tool_calls_total',
  help: 'Total number of MCP tool invocations',
  labelNames: ['tool', 'status'] as const,
  registers: [register],
});

const toolDurationSeconds = new Histogram({
  name: 'mcp_tool_duration_seconds',
  help: 'Duration of MCP tool execution in seconds',
  labelNames: ['tool'] as const,
  registers: [register],
});

const httpRequestsTotal = new Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'path', 'status_code'] as const,
  registers: [register],
});

const httpRequestDurationSeconds = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'path'] as const,
  registers: [register],
});

export function withMetrics<TArgs, TResult>(
  toolName: string,
  handler: (args: TArgs) => Promise<TResult>,
): (args: TArgs) => Promise<TResult> {
  return async (args: TArgs): Promise<TResult> => {
    const end = toolDurationSeconds.startTimer({ tool: toolName });
    try {
      const result = await handler(args);
      const status = (result as any)?.isError ? 'error' : 'success';
      toolCallsTotal.inc({ tool: toolName, status });
      return result;
    } catch (error) {
      toolCallsTotal.inc({ tool: toolName, status: 'error' });
      throw error;
    } finally {
      end();
    }
  };
}

export function httpMetrics(req: any, res: any, next: any): void {
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const durationSec = Number(process.hrtime.bigint() - start) / 1e9;
    const path = req.path;
    httpRequestsTotal.inc({ method: req.method, path, status_code: String(res.statusCode) });
    httpRequestDurationSeconds.observe({ method: req.method, path }, durationSec);
  });
  next();
}

export async function getMetrics(): Promise<{ contentType: string; metrics: string }> {
  return {
    contentType: register.contentType,
    metrics: await register.metrics(),
  };
}
```

### Key points about metrics.ts

- MCP tool metrics (`mcp_tool_*`) and HTTP metrics (`http_*`) are separate. Never aggregate them.
- `withMetrics()` is a higher-order function that wraps tool handler callbacks. It detects `isError: true` on the return value to record `status=error`.
- `httpMetrics` is Express middleware. Register it before all routes with `app.use(httpMetrics)`.
- The MCP SDK v2 has no middleware or lifecycle hooks. `withMetrics()` wrapping at `registerTool` time is the only instrumentation point.

## src/server.ts — Full Structure

```typescript
import express from 'express';
import { McpServer, createMcpHandler } from '@modelcontextprotocol/server';
import { toNodeHandler } from '@modelcontextprotocol/node';
import { z } from 'zod';
import { withMetrics, httpMetrics, getMetrics } from './metrics.js';

function log(level: string, event: string, data: Record<string, unknown> = {}) {
  process.stderr.write(
    JSON.stringify({ timestamp: new Date().toISOString(), level, event, ...data }) + '\n'
  );
}

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

// --- MCP Handler ---

const handler = createMcpHandler(() => {
  const server = new McpServer(
    { name: '{{APP_NAME}}', version: '2.0.0' },
    { capabilities: { tools: {} } },
  );

  // Register tools here (see Tool Registration Pattern below)

  return server;
});

// --- Express App ---

const app = express();
app.use(httpMetrics);

app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok', service: '{{APP_NAME}}' });
});

app.get('/ready', (_req, res) => {
  res.status(200).json({ status: 'ready', service: '{{APP_NAME}}' });
});

app.get('/metrics', async (_req, res) => {
  const { contentType, metrics } = await getMetrics();
  res.set('Content-Type', contentType);
  res.status(200).send(metrics);
});

const nodeHandler = toNodeHandler(handler);
app.all('/mcp', (req, res) => { void nodeHandler(req, res); });

const port = parseInt(process.env.PORT || '8080', 10);
app.listen(port, () => log('info', 'server_start', { port }));

process.on('SIGTERM', async () => {
  log('info', 'shutdown_initiated');
  await handler.close();
  process.exit(0);
});
```

## Tool Registration Pattern

Every tool follows this pattern:

```typescript
server.registerTool('tool-name', {
  description: 'Clear description of what the tool does and when to use it',
  inputSchema: {
    requiredParam: z.string().describe('What this parameter is'),
    optionalParam: z.number().optional().describe('What this optional parameter does'),
  },
}, withMetrics('tool-name', async ({ requiredParam, optionalParam }) => {
  try {
    const result = await doSomething(requiredParam, optionalParam);
    return toolResult(result);
  } catch (error) {
    log('error', 'tool_error', { tool: 'tool-name', error: String(error) });
    return toolError(error);
  }
}));
```

Rules:
- The first argument to `withMetrics()` must match the tool name string exactly
- Always wrap the callback with `withMetrics()`
- Use try/catch inside the callback — return `toolError()` for caught errors
- Use `z.string()`, `z.number()`, `z.boolean()`, `z.enum()`, `z.array()` for input schemas
- Add `.describe()` to every schema field — the MCP client reads these descriptions
- Add `.optional()` for non-required parameters

## Readiness Probe with Database

If your server connects to a database, the readiness probe should verify the connection:

```typescript
app.get('/ready', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'ready', service: '{{APP_NAME}}', database: 'connected' });
  } catch (error) {
    res.status(503).json({
      status: 'not ready',
      error: error instanceof Error ? error.message : String(error),
    });
  }
});
```

## Graceful Shutdown with Resources

If your server holds resources (DB pools, model handles), close them in the SIGTERM handler:

```typescript
process.on('SIGTERM', async () => {
  log('info', 'shutdown_initiated');
  await handler.close();
  await pool.end();           // Close DB pool
  process.exit(0);
});
```
