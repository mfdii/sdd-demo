import { Registry, Counter, Histogram, Gauge, collectDefaultMetrics } from 'prom-client';

const register = new Registry();

collectDefaultMetrics({ register });

new Gauge({
  name: 'mcp_server_info',
  help: 'MCP server identification',
  labelNames: ['name', 'version'] as const,
  registers: [register],
}).set({ name: 'mcp-hello-world', version: '2.0.0' }, 1);

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
