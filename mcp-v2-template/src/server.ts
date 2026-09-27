import express from 'express';
import { McpServer, createMcpHandler } from '@modelcontextprotocol/server';
import { toNodeHandler } from '@modelcontextprotocol/node';
import { z } from 'zod';
import { withMetrics, httpMetrics, getMetrics } from './metrics.js';

function log(level: string, event: string, data: Record<string, unknown> = {}) {
  process.stderr.write(JSON.stringify({ timestamp: new Date().toISOString(), level, event, ...data }) + '\n');
}

function toolResult(result: unknown) {
  return { content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }] };
}

function toolError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return { content: [{ type: 'text' as const, text: JSON.stringify({ error: message }, null, 2) }], isError: true as const };
}

// --- MCP Handler (stateless: new McpServer instance per request) ---

const handler = createMcpHandler(() => {
  const server = new McpServer(
    { name: 'mcp-hello-world', version: '2.0.0' },
    { capabilities: { tools: {} } },
  );

  // --- Register your tools below ---

  server.registerTool('hello', {
    description: 'A simple hello world tool to verify the server is working',
    inputSchema: {
      name: z.string().describe('Name to greet').optional(),
    },
  }, withMetrics('hello', async ({ name }) => {
    try {
      return toolResult({ message: `Hello, ${name || 'world'}!` });
    } catch (error) {
      log('error', 'tool_error', { tool: 'hello', error: String(error) });
      return toolError(error);
    }
  }));

  // --- End tool registration ---

  return server;
});

// --- Express app ---

const app = express();
app.use(httpMetrics);

app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok', service: 'mcp-hello-world' });
});

app.get('/ready', (_req, res) => {
  res.status(200).json({ status: 'ready', service: 'mcp-hello-world' });
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
