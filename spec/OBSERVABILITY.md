# Observability Specification

## Metrics Architecture

Every MCP server exposes two separate metric families at `GET /metrics` in Prometheus text exposition format. These are never aggregated.

### MCP Tool Metrics

Measure tool handler execution — what the server does.

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `mcp_tool_calls_total` | Counter | `tool`, `status` | Total tool invocations. `status` is `success` or `error`. |
| `mcp_tool_duration_seconds` | Histogram | `tool` | Tool handler execution duration (excluding HTTP overhead). |
| `mcp_server_info` | Gauge | `name`, `version` | Static server identification. Always value 1. |

### HTTP Metrics

Measure transport-level behavior — how the server handles traffic.

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `http_requests_total` | Counter | `method`, `path`, `status_code` | Total HTTP requests. |
| `http_request_duration_seconds` | Histogram | `method`, `path` | Full HTTP round-trip duration. |

### Process Metrics

Automatically collected by `prom-client`'s `collectDefaultMetrics()`:

- `process_cpu_seconds_total` — CPU time
- `process_resident_memory_bytes` — RSS memory
- `nodejs_heap_size_used_bytes` — V8 heap used
- `nodejs_heap_size_total_bytes` — V8 heap total
- `nodejs_eventloop_lag_seconds` — Event loop lag
- `nodejs_gc_duration_seconds` — GC pause duration

### Label Cardinality

Keep total series under 200 per server. The budget:
- Tools: max ~30 tools × 2 statuses = 60 series
- HTTP paths: ~5 paths × 3 methods × ~10 status codes = ~150 series (in practice much less)
- Process metrics: ~15 series

If your server has high-cardinality paths (e.g., `/api/items/:id`), normalize them in the `httpMetrics` middleware:

```typescript
export function httpMetrics(req: any, res: any, next: any): void {
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const durationSec = Number(process.hrtime.bigint() - start) / 1e9;
    // Normalize high-cardinality paths
    let path = req.path;
    path = path.replace(/\/items\/[^/]+/, '/items/:id');
    httpRequestsTotal.inc({ method: req.method, path, status_code: String(res.statusCode) });
    httpRequestDurationSeconds.observe({ method: req.method, path }, durationSec);
  });
  next();
}
```

## ServiceMonitor

### k8s/servicemonitor.yaml

```yaml
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{APP_NAME}}
  labels:
    app: {{APP_NAME}}
spec:
  selector:
    matchLabels:
      app: {{APP_NAME}}
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
```

- Deployed to the **app namespace** (same as the workload)
- Requires user-workload monitoring to be enabled on the cluster:
  ```yaml
  # ConfigMap: cluster-monitoring-config in openshift-monitoring
  data:
    config.yaml: |
      enableUserWorkload: true
  ```
- The `port: http` must match the Service port name
- After applying, verify the target appears in OCP Console → Observe → Targets

## Perses Dashboard

### k8s/dashboard.yaml

```yaml
---
apiVersion: perses.dev/v1alpha2
kind: PersesDashboard
metadata:
  name: {{APP_NAME}}
  labels:
    app.kubernetes.io/name: mcp-dashboards
spec:
  config:
    display:
      description: {{APP_NAME}} MCP server tool calls, HTTP traffic, and resource usage
      name: {{APP_DISPLAY_NAME}}
    duration: 1h
    layouts:
    - kind: Grid
      spec:
        display:
          collapse:
            open: true
          title: Overview
        items:
        - content:
            $ref: '#/spec/panels/toolCalls'
          height: 5
          width: 6
          x: 0
          "y": 0
        - content:
            $ref: '#/spec/panels/errorRate'
          height: 5
          width: 6
          x: 6
          "y": 0
        - content:
            $ref: '#/spec/panels/avgDuration'
          height: 5
          width: 6
          x: 12
          "y": 0
        - content:
            $ref: '#/spec/panels/httpReqRate'
          height: 5
          width: 6
          x: 18
          "y": 0
    - kind: Grid
      spec:
        display:
          collapse:
            open: true
          title: Tool Metrics
        items:
        - content:
            $ref: '#/spec/panels/toolCallRate'
          height: 10
          width: 8
          x: 0
          "y": 0
        - content:
            $ref: '#/spec/panels/toolErrors'
          height: 10
          width: 8
          x: 8
          "y": 0
        - content:
            $ref: '#/spec/panels/toolDurationP95'
          height: 10
          width: 8
          x: 16
          "y": 0
    - kind: Grid
      spec:
        display:
          collapse:
            open: true
          title: HTTP Metrics
        items:
        - content:
            $ref: '#/spec/panels/httpRequestRate'
          height: 10
          width: 12
          x: 0
          "y": 0
        - content:
            $ref: '#/spec/panels/httpDurationP95'
          height: 10
          width: 12
          x: 12
          "y": 0
    - kind: Grid
      spec:
        display:
          collapse:
            open: true
          title: Resources
        items:
        - content:
            $ref: '#/spec/panels/memoryUsage'
          height: 10
          width: 12
          x: 0
          "y": 0
        - content:
            $ref: '#/spec/panels/cpuUsage'
          height: 10
          width: 12
          x: 12
          "y": 0
    panels:
      toolCalls:
        kind: Panel
        spec:
          display:
            description: Total tool invocations in the last hour
            name: Tool Calls (1h)
          plugin:
            kind: StatChart
            spec:
              calculation: last
              format:
                shortValues: true
                unit: decimal
              sparkline: {}
          queries:
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: sum(increase(mcp_tool_calls_total{job="{{APP_NAME}}"}[1h]))
      errorRate:
        kind: Panel
        spec:
          display:
            description: Percentage of tool calls resulting in errors
            name: Error Rate
          plugin:
            kind: StatChart
            spec:
              calculation: last
              format:
                unit: percent
              sparkline: {}
              thresholds:
                steps:
                - color: green
                  value: 0
                - color: yellow
                  value: 1
                - color: red
                  value: 5
          queries:
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: sum(rate(mcp_tool_calls_total{job="{{APP_NAME}}",status="error"}[5m])) / sum(rate(mcp_tool_calls_total{job="{{APP_NAME}}"}[5m])) * 100
      avgDuration:
        kind: Panel
        spec:
          display:
            description: Average tool execution duration
            name: Avg Duration
          plugin:
            kind: StatChart
            spec:
              calculation: last
              format:
                decimalPlaces: 2
                unit: seconds
              sparkline: {}
              thresholds:
                steps:
                - color: green
                  value: 0
                - color: yellow
                  value: 1
                - color: red
                  value: 5
          queries:
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: sum(rate(mcp_tool_duration_seconds_sum{job="{{APP_NAME}}"}[5m])) / sum(rate(mcp_tool_duration_seconds_count{job="{{APP_NAME}}"}[5m]))
      httpReqRate:
        kind: Panel
        spec:
          display:
            description: HTTP requests per second
            name: HTTP Req/s
          plugin:
            kind: StatChart
            spec:
              calculation: last
              format:
                decimalPlaces: 2
                unit: decimal
              sparkline: {}
          queries:
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: sum(rate(http_requests_total{job="{{APP_NAME}}"}[5m]))
      toolCallRate:
        kind: Panel
        spec:
          display:
            description: Rate of tool invocations per second by tool name
            name: Tool Call Rate
          plugin:
            kind: TimeSeriesChart
            spec:
              yAxis:
                label: calls/s
          queries:
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: sum(rate(mcp_tool_calls_total{job="{{APP_NAME}}"}[5m])) by (tool)
                  seriesNameFormat: '{{tool}}'
      toolErrors:
        kind: Panel
        spec:
          display:
            description: Rate of tool errors per second by tool name
            name: Tool Errors
          plugin:
            kind: TimeSeriesChart
            spec:
              yAxis:
                label: errors/s
          queries:
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: sum(rate(mcp_tool_calls_total{job="{{APP_NAME}}",status="error"}[5m])) by (tool)
                  seriesNameFormat: '{{tool}}'
      toolDurationP95:
        kind: Panel
        spec:
          display:
            description: 95th percentile tool execution duration
            name: Tool Duration p95
          plugin:
            kind: TimeSeriesChart
            spec:
              yAxis:
                label: seconds
          queries:
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: histogram_quantile(0.95, sum(rate(mcp_tool_duration_seconds_bucket{job="{{APP_NAME}}"}[5m])) by (tool, le))
                  seriesNameFormat: '{{tool}}'
      httpRequestRate:
        kind: Panel
        spec:
          display:
            description: HTTP request rate by path
            name: HTTP Request Rate
          plugin:
            kind: TimeSeriesChart
            spec:
              yAxis:
                label: req/s
          queries:
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: sum(rate(http_requests_total{job="{{APP_NAME}}"}[5m])) by (path)
                  seriesNameFormat: '{{path}}'
      httpDurationP95:
        kind: Panel
        spec:
          display:
            description: 95th percentile HTTP request duration by path
            name: HTTP Duration p95
          plugin:
            kind: TimeSeriesChart
            spec:
              yAxis:
                label: seconds
          queries:
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job="{{APP_NAME}}"}[5m])) by (path, le))
                  seriesNameFormat: '{{path}}'
      memoryUsage:
        kind: Panel
        spec:
          display:
            description: Process memory usage
            name: Memory Usage
          plugin:
            kind: TimeSeriesChart
            spec:
              yAxis:
                label: bytes
          queries:
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: process_resident_memory_bytes{job="{{APP_NAME}}"}
                  seriesNameFormat: RSS
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: nodejs_heap_size_used_bytes{job="{{APP_NAME}}"}
                  seriesNameFormat: Heap Used
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: nodejs_heap_size_total_bytes{job="{{APP_NAME}}"}
                  seriesNameFormat: Heap Total
      cpuUsage:
        kind: Panel
        spec:
          display:
            description: CPU usage in cores
            name: CPU Usage
          plugin:
            kind: TimeSeriesChart
            spec:
              yAxis:
                label: cores
          queries:
          - kind: TimeSeriesQuery
            spec:
              plugin:
                kind: PrometheusTimeSeriesQuery
                spec:
                  datasource:
                    kind: PrometheusDatasource
                  query: rate(process_cpu_seconds_total{job="{{APP_NAME}}"}[5m])
                  seriesNameFormat: CPU
```

Key points:
- Dashboard is deployed to `openshift-cluster-observability-operator` namespace, NOT the app namespace
- Replace `{{APP_NAME}}` in all PromQL queries with your server name (must match the Kubernetes Service name, which becomes the Prometheus `job` label)
- Replace `{{APP_DISPLAY_NAME}}` with a human-readable name (e.g., "Weather MCP")
- 4 grid layouts: Overview (4 stat charts), Tool Metrics (3 time series), HTTP Metrics (2 time series), Resources (2 time series)

## Domain-Specific Metrics

For servers backed by a data store, add custom gauges that report data health. These are refreshed on a 60-second interval, not on every scrape.

Add to `src/metrics.ts`:

```typescript
const itemsTotal = new Gauge({
  name: '{{APP_NAME}}_items_total',
  help: 'Total items in the database',
  registers: [register],
});

async function refreshDomainMetrics(pool: any): Promise<void> {
  try {
    const result = await pool.query('SELECT COUNT(*) FROM items');
    itemsTotal.set(Number(result.rows[0].count));
  } catch {
    // DB unavailable — gauges keep their last value
  }
}

let domainInterval: ReturnType<typeof setInterval> | null = null;

export function startDomainMetrics(pool: any): void {
  refreshDomainMetrics(pool);
  domainInterval = setInterval(() => refreshDomainMetrics(pool), 60_000);
  domainInterval.unref();  // Don't prevent graceful shutdown
}
```

Call `startDomainMetrics(pool)` after the database connection is verified in `src/server.ts`.
