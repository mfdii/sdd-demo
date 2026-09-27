# Security Specification

## Zero-CVE Mandate

Every MCP server must pass `npm audit` with **zero critical and zero high vulnerabilities**. This is a hard gate — do not deploy code that fails this check.

```bash
# Run after every dependency change
npm audit

# Expected output
found 0 vulnerabilities
```

If vulnerabilities are found:
1. Check if a patched version exists: `npm audit fix`
2. If no patch, check if the vulnerability applies to your usage (server-side, not browser)
3. If it applies, find an alternative package from the approved list or ask for an exception
4. Never use `npm audit fix --force` (it may introduce breaking changes)

## Approved Dependencies

Only these packages are approved for use without additional review:

### Core (required in every server)

| Package | Purpose | CVE Status |
|---------|---------|------------|
| `@modelcontextprotocol/server` | MCP SDK | Clean |
| `@modelcontextprotocol/node` | Node.js HTTP adapter | Clean |
| `express` | HTTP framework | Clean |
| `prom-client` | Prometheus metrics | Clean |
| `zod` | Schema validation | Clean |

### Optional (use when needed)

| Package | Purpose | When to Use |
|---------|---------|-------------|
| `pg` | PostgreSQL client | Database-backed servers |
| `@xenova/transformers` | ML inference (ONNX) | Embedding/sentiment servers |
| `node-fetch` | HTTP client | Only if native `fetch` is insufficient (Node 26 has native fetch) |

### Prohibited

Do not use:
- `axios`, `got`, `superagent` — use native `fetch()`
- `lodash`, `ramda`, `underscore` — use native JS
- `moment`, `dayjs` — use native `Date` and `Intl`
- `dotenv` — use OCP Secrets and env var injection
- `winston`, `bunyan`, `pino` — use the structured `log()` helper
- `helmet`, `cors` — not needed behind OCP route
- Any package with native/C++ bindings unless on the approved list (breaks distroless)

Any dependency not on the approved list requires explicit user approval before adding.

## Container Security

### Security Context (enforced in deployment.yaml)

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
```

- `runAsNonRoot: true` — OpenShift SCC assigns a random UID. Do not set `runAsUser`.
- `drop: [ALL]` — No Linux capabilities. Node.js does not need any.
- `seccompProfile: RuntimeDefault` — Blocks dangerous syscalls.

### Distroless Runtime

The Hummingbird runtime image (`registry.access.redhat.com/hi/nodejs:26`) is distroless:
- No shell (`/bin/sh`, `/bin/bash`)
- No package manager
- No `curl`, `wget`, or system utilities
- Attack surface limited to Node.js runtime and your application code

This is intentional. Do not switch to a non-distroless image to "make debugging easier."

## Input Validation

All tool inputs are validated by Zod schemas defined in `inputSchema`. This is automatic — the MCP SDK validates inputs before the handler runs.

Additional rules:
- Never use `eval()`, `Function()`, or `vm.runInNewContext()`
- Never use `child_process.exec()` or `child_process.execSync()` — if you must run a subprocess, use `child_process.execFile()` with explicit arguments (no shell interpolation)
- Never construct SQL with template literals — use parameterized queries: `pool.query('SELECT * FROM t WHERE id = $1', [id])`
- Never construct URLs from user input without validation

## Secrets Management

- Never commit secrets to git (API keys, passwords, tokens)
- Never put secrets in Kubernetes manifests as plaintext
- Use OCP Secrets: `oc create secret generic <name> --from-literal=KEY=value`
- Reference secrets in deployment.yaml via `secretKeyRef`
- If a tool needs an API key, read it from `process.env.API_KEY` — the secret is injected by the Deployment

## Dependency Updates

When updating dependencies:
1. Run `npm update`
2. Run `npm audit` — must remain at zero critical/high
3. Run `npm run build` — must compile cleanly
4. Test all endpoints locally
5. Commit updated `package.json` and `package-lock.json` together
