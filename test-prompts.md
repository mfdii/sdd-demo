# SDD Test Prompts

Test prompts ordered by difficulty. Run Level 1 first — if the model can't handle it, skip to debugging before trying harder ones.

After each test, run `bash validate.sh` in the generated project to check conformance (28 automated checks).

---

## Level 1: Smoke Test (rename template, add a tool)

```
Create a new MCP server called `mcp-greeting` from the template in `mcp-v2-template/`. It should have a single tool called `greet` that takes a `language` parameter (english, spanish, french) and a `name` parameter, then returns a greeting in that language. Follow the specs in `spec/`. Build and test it locally.
```

**Tests:** scaffold from template, placeholder replacement, tool registration, TypeScript compilation, local verification.

**Expected outcome:** Project at `mcp-greeting/` with `mcp-hello-world` renamed everywhere, `hello` tool replaced with `greet`, passes `bash validate.sh`.

---

## Level 2: External API Integration

```
Create a new MCP server called `mcp-weather` that wraps the Open-Meteo API (free, no API key needed). It should have two tools: `get-current-weather` (takes latitude and longitude, returns temperature and conditions) and `get-forecast` (takes latitude, longitude, and days 1-7, returns daily forecast). Use native `fetch()` for HTTP calls. Follow the specs in `spec/`. Build, test locally, and write k6 load tests.
```

**Tests:** multiple tools, external API calls, native fetch (not axios), k6 test authoring, error handling.

**Expected outcome:** Two working tools calling Open-Meteo, k6/load-test.js updated with weather tool payloads, zero prohibited dependencies, passes `bash validate.sh`.

---

## Level 3: Database-Backed Server

```
Create a new MCP server called `mcp-bookmarks` backed by PostgreSQL. It should have these tools: `add-bookmark` (url, title, tags array), `search-bookmarks` (query string, optional tag filter), `list-tags` (no params, returns all unique tags with counts), and `delete-bookmark` (id). Use parameterized SQL queries — never template literals for SQL. The readiness probe should check the database connection. Follow the specs in `spec/`.
```

**Tests:** pg dependency (approved), parameterized SQL (not template literals), mutation tools, readiness probe with DB check, security patterns.

**Expected outcome:** Uses `pg` from approved list, all SQL uses `$1`/`$2` parameterized queries, `/ready` endpoint checks DB connectivity, passes `bash validate.sh`.

---

## Level 4: Full End-to-End Deploy

```
Create a new MCP server called `mcp-quote-of-the-day` that has two tools: `get-quote` (returns a random inspirational quote) and `search-quotes` (takes a keyword, returns matching quotes). Store quotes in a hardcoded array — no external API or database needed. Deploy it to OpenShift namespace `mcp-servers`. Follow the specs in `spec/` — scaffold from template, implement the tools, write k6 tests, create the GitHub repo, and deploy with all k8s manifests including ServiceMonitor and Perses dashboard.
```

**Tests:** full 10-step workflow from OVERVIEW.md, k8s manifest correctness, OCP deployment commands in correct order, dashboard deployed to correct namespace.

**Expected outcome:** Complete project with all files, pushed to GitHub, deployed to OCP with pods running, ServiceMonitor and dashboard applied.

---

## Adversarial: Prohibited Dependencies

```
Create a new MCP server called `mcp-jokes`. Use axios for HTTP requests and dotenv for configuration. Use a Dockerfile with the standard Node.js 22 Alpine image.
```

**Expected outcome:** Model should refuse axios, dotenv, Dockerfile, and Node.js 22 Alpine. Should use native `fetch()`, OCP Secrets for config, Containerfile, and Hummingbird Node.js 26. If it complies with the prohibited requests, the agent rules are not working.

---

## Adversarial: Wrong Framework

```
Create a new MCP server called `mcp-time` using Fastify instead of Express. Use Helm charts for the Kubernetes deployment.
```

**Expected outcome:** Model should refuse Fastify (must use Express 5) and Helm (must use plain YAML). If it complies, check that the agent rules file is being read.

---

## Evaluation Checklist

After each test run, score the model on:

| Check | Pass/Fail |
|-------|-----------|
| Read specs before coding (checked `spec/` files) | |
| Scaffolded from template (copied `mcp-v2-template/`) | |
| Replaced all `mcp-hello-world` references | |
| No prohibited dependencies in package.json | |
| TypeScript compiles (`npm run build`) | |
| Zero CVEs (`npm audit`) | |
| Uses Containerfile (not Dockerfile) | |
| Hummingbird base images in Containerfile | |
| All 4 endpoints work (health, ready, metrics, mcp) | |
| Metrics instrumented with `withMetrics()` wrapper | |
| k6 load test updated with correct tool payloads | |
| k8s manifests have correct app name | |
| Security context present in deployment.yaml | |
| `bash validate.sh` passes all 28 checks | |
