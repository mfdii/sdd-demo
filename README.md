# SDD Demo: Spec Driven Development for MCP v2 Servers

Spec Driven Development (SDD) uses a specification suite as the single source of truth for building software with coding agents. Instead of relying on the model to make architectural decisions, the specs define every pattern — from file structure to security policy — and the agent follows them.

This repo contains a complete SDD specification suite, a reference template, and conformance validation for building [MCP v2](https://modelcontextprotocol.io/) servers on OpenShift. A coding agent reads the specs, scaffolds from the template, implements tools, and runs validation — producing a conformant, deployable server.

## How It Works

```
spec/           Specification suite (7 documents)
mcp-v2-template/  Reference implementation (hello-world MCP server)
AGENTS.md       Agent rules for OpenCode
test-prompts.md   Test prompts at increasing difficulty
```

The agent follows this workflow:

1. **Read specs** — `spec/OVERVIEW.md` is the entry point, links to ARCHITECTURE, IMPLEMENTATION, INFRASTRUCTURE, SECURITY, OBSERVABILITY, TESTING, and ENVIRONMENT specs
2. **Scaffold** — Copy the template, run `rename.sh` to replace all references, install dependencies
3. **Implement** — Rewrite `src/server.ts` with custom tools following the patterns in the spec
4. **Validate** — Run `validate.sh` (28 conformance checks: build, structure, security, customization, endpoints)

## Quick Start with OpenCode + Nemotron

This demo uses [OpenCode](https://opencode.ai) as the coding agent CLI paired with **NVIDIA Nemotron 3.5 Lightning 30B A3B** ([Q4_0 GGUF](https://huggingface.co/nvidia/Nemotron-3.5-Lightning-30B-A3B)) served by [llama.cpp](https://github.com/ggml-org/llama.cpp) (build 11118, Vulkan backend) on Red Hat OpenShift AI 3.5.1 / OpenShift 4.22. OpenCode is model-agnostic and connects to any OpenAI-compatible endpoint.

### 1. Install OpenCode

```bash
# macOS
brew install anomalyco/tap/opencode-v2

# Or via npm
npm install -g opencode
```

### 2. Configure your model endpoint

Create `~/.config/opencode/opencode.json`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "your-provider/your-model",
  "providers": {
    "your-provider": {
      "name": "Your Provider",
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": {
        "baseURL": "https://your-endpoint.example.com/v1"
      },
      "models": {
        "your-model": {
          "name": "Your Model Display Name"
        }
      }
    }
  }
}
```

For example, to connect to a Nemotron model served by llama.cpp on OpenShift:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "my-cluster/nemotron-30b",
  "providers": {
    "my-cluster": {
      "name": "My Cluster",
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": {
        "baseURL": "https://nemotron-route.apps.your-cluster.example.com/v1"
      },
      "models": {
        "nemotron-30b": {
          "name": "Nemotron 30B"
        }
      }
    }
  }
}
```

If your endpoint requires authentication, add an `env` field and set the environment variable:

```jsonc
{
  "providers": {
    "your-provider": {
      "env": ["YOUR_API_KEY"],
      // ...
    }
  }
}
```

### 3. Run a test prompt

```bash
cd sdd-demo
opencode
```

Then paste a prompt:

```
Create a new MCP server called `mcp-greeting` from the template in
`mcp-v2-template/`. It should have a single tool called `greet` that
takes a `language` parameter (english, spanish, french) and a `name`
parameter, then returns a greeting in that language. Follow the specs
in `spec/`. Build and test it locally.
```

The agent reads the specs, scaffolds, implements, builds, and validates — producing a conformant MCP server.

## Test Prompts

Six test prompts in `test-prompts.md` cover increasing difficulty:

| Level | Prompt | What It Tests |
|-------|--------|---------------|
| 1 | Greeting server | Scaffold, rename, single tool, validate |
| 2 | Weather server (Open-Meteo API) | Multiple tools, external API, native fetch, k6 tests |
| 3 | Bookmarks server (PostgreSQL) | `pg` dependency, parameterized SQL, mutation tools, DB readiness |
| 4 | Quote-of-the-day (full deploy) | End-to-end: scaffold through OpenShift deployment |
| A1 | Prohibited dependencies | Adversarial: should refuse axios, dotenv, Dockerfile |
| A2 | Wrong framework | Adversarial: should refuse Fastify, Helm |

## Spec Index

| Spec | Purpose |
|------|---------|
| [OVERVIEW.md](spec/OVERVIEW.md) | Entry point, workflow, directory layout |
| [ARCHITECTURE.md](spec/ARCHITECTURE.md) | MCP v2 stateless pattern, dependency stack |
| [IMPLEMENTATION.md](spec/IMPLEMENTATION.md) | Code patterns with exact snippets |
| [INFRASTRUCTURE.md](spec/INFRASTRUCTURE.md) | OpenShift 4.22, Containerfile, k8s manifests |
| [SECURITY.md](spec/SECURITY.md) | Zero-CVE mandate, approved dependencies |
| [OBSERVABILITY.md](spec/OBSERVABILITY.md) | Prometheus metrics, ServiceMonitor, Perses dashboards |
| [TESTING.md](spec/TESTING.md) | k6 load testing scenarios and thresholds |
| [ENVIRONMENT.md](spec/ENVIRONMENT.md) | Dev environment, shell commands, file editing |

## Validation

The template includes `validate.sh` which runs 28 automated conformance checks:

- **Build** — TypeScript compiles, zero CVEs
- **Structure** — Containerfile exists (no Dockerfile), ESM module, k8s manifests, k6 tests, ServiceMonitor, dashboard
- **Security** — No prohibited dependencies, no eval/exec, security context, drop ALL capabilities
- **Customization** — App renamed, hello tool removed, custom tool registered with `withMetrics`, description updated, no template references remaining
- **Endpoints** — Starts the server and verifies `/health`, `/ready`, `/metrics`, `/mcp` all respond correctly

## Performance: Nemotron 3.5 Lightning 30B on AMD Radeon AI PRO R9700

All tests ran against a single NVIDIA Nemotron 3.5 Lightning 30B A3B (Q4_0 GGUF, 17GB) served by llama.cpp build 11118 (`ghcr.io/ggml-org/llama.cpp:server-vulkan`) on an AMD Radeon AI PRO R9700 GPU (32GB VRAM) running on Red Hat OpenShift AI 3.5.1 / OpenShift 4.22.

### Inference Performance

| Metric | Value |
|--------|-------|
| Token generation throughput | **120 tokens/sec** |
| Prompt processing throughput | **2,000 tokens/sec** |
| Prompt cache hit rate | **96.9%** |
| Total tokens generated | **66.6K** |
| Total prompt tokens processed | **237K** |
| Total wall-clock time (all 4 levels) | **~14 minutes** |

### Coding Agent Session Metrics

| Session | Output Tokens | Generation Time | Tokens/sec | Result |
|---------|--------------|-----------------|------------|--------|
| Level 1: Greeting | 11,726 | 136s | **86 t/s** | 28/28 pass |
| Level 2: Weather | 12,499 | 149s | **84 t/s** | 28/28 pass |
| Level 3: Bookmarks | 17,079 | 241s | **71 t/s** | 28/28 pass |
| Level 4: Quote (full deploy) | 18,344 | 587s | **31 t/s** | 28/28 pass, deployed to OCP |

Level 4 TPS dropped because the agent got stuck in a build retry loop (`npm ci` failure) before self-correcting. Levels 1-3 sustained 71-86 t/s throughout, which represents the model's effective throughput during productive coding.

### MCP Server Performance (Production)

From the deployed `mcp-quote-of-the-day` on OpenShift:

| Metric | Value |
|--------|-------|
| `get-quote` p50 latency | **< 5ms** |
| `search-quotes` p50 latency | **< 5ms** |
| Tool success rate | **100%** (11/11 calls) |

## Platform Stack

| Component | Version |
|-----------|---------|
| MCP Specification | 2026-07-28 |
| MCP SDK | @modelcontextprotocol/server 2.1.0 |
| Architecture | Stateless (new McpServer per request) |
| Node.js | >= 26 |
| TypeScript | 5.9.x, strict mode, ESM-only |
| Express | 5.x |
| AI Platform | Red Hat OpenShift AI 3.5.1 |
| Platform | OpenShift 4.22 / Kubernetes 1.35 |
| Container images | Red Hat Hummingbird distroless (nodejs:26) |
| Observability | Prometheus + Perses dashboards |
| Load testing | k6 |

## Why SDD?

Traditional prompting relies on the model knowing the right patterns. SDD removes that dependency:

- **Deterministic scaffolding** — `rename.sh` handles find-and-replace across all files. No manual editing of template references.
- **Automated validation** — `validate.sh` catches conformance gaps before deployment. The agent runs it and self-corrects.
- **Spec as guardrail** — The agent can't reach for axios, Dockerfile, Helm, or Fastify because the spec says no. Adversarial prompts confirmed this works.
- **Model-agnostic** — The specs work with any model that can read files and run shell commands. We tested with Nemotron (OpenCode), Qwen3-Coder (Continue.dev), and Nemotron (Cline). OpenCode produced the cleanest results.

The key insight: make non-deterministic operations (file editing, find-and-replace, deployment ordering) into deterministic scripts that the model invokes rather than reimplements.
