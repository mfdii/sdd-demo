# Development Environment Specification

## Platform

| Component | Value |
|-----------|-------|
| OS | macOS (Darwin) |
| Shell | zsh |
| Node.js | >= 26 (installed via nvm or brew) |
| Package manager | npm (not yarn, not pnpm) |
| Container runtime | Podman or Docker (builds run on OpenShift, not locally) |
| k6 | Installed via `brew install k6` |

## Shell Commands: Required Patterns

These patterns avoid known macOS/zsh pitfalls. Use them exactly as written.

### Text replacement across files

**Always use `perl`, never `sed`.** macOS `sed -i` requires a backup extension (`sed -i ''`) that differs from GNU `sed -i`. Perl works identically on both.

```bash
# CORRECT — perl in-place replacement, excluding node_modules/dist/.git
find . -type f \( -name '*.ts' -o -name '*.js' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.sh' -o -name '*.md' \) \
  -not -path '*/node_modules/*' \
  -not -path '*/dist/*' \
  -not -path '*/.git/*' \
  -exec perl -pi -e 's/old-value/new-value/g' {} \;

# WRONG — corrupts binaries in node_modules
find . -type f | xargs sed -i 's/old/new/g'

# WRONG — macOS sed fails without backup extension
sed -i 's/old/new/g' file.ts
```

### File search

```bash
# CORRECT — exclude generated directories
grep -r 'pattern' --include='*.ts' --include='*.json' --include='*.yaml' .

# WRONG — searches node_modules and binary files
grep -r 'pattern' .
```

### Process management

```bash
# Kill anything on port 8080 before starting a server
lsof -ti:8080 | xargs kill -9 2>/dev/null; sleep 1

# Start server in background for testing
npm start &
SERVER_PID=$!
sleep 2

# Clean up
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null
```

### npm commands

```bash
# Install dependencies
npm install

# Build (always use the npm script, never call tsc directly)
npm run build

# Check for vulnerabilities
npm audit

# NEVER use npm audit fix --force
```

## File Editing Strategy

When modifying source files, follow this priority:

1. **Full file rewrite via `write_to_file`** — When replacing a tool implementation or making structural changes to `server.ts`, use Cline's native `write_to_file` tool to write the entire file. This is the most reliable approach. **Do NOT use heredocs (`cat << EOF`) in the terminal** — Cline's shell integration garbles multi-line heredocs, producing corrupted files.

2. **Targeted perl replacement** — For simple find-and-replace across multiple files (like renaming the app):
   ```bash
   perl -pi -e 's/old-name/new-name/g' src/server.ts src/metrics.ts package.json
   ```

3. **Never use patch/diff formats** — They are fragile and fail when context lines don't match exactly. Always prefer full file rewrites or targeted replacements.

4. **Never use heredocs** — `cat > file << 'EOF'` and `cat > file << EOF` both fail in this environment due to terminal shell integration issues. The output is garbled and will corrupt your files. Always use `write_to_file` instead.

## Directory Exclusions

When running any command that traverses the file tree, **always exclude**:

| Directory | Why |
|-----------|-----|
| `node_modules/` | Contains thousands of third-party files — never modify, search, or count these |
| `dist/` | Generated output — rebuilt by `npm run build` |
| `.git/` | Repository metadata — never touch |
| `package-lock.json` | Auto-generated — never manually edit, never search-and-replace inside it |

The `rename.sh` script in the template handles these exclusions automatically. Always use it for renaming.

## Template Workflow Scripts

The template includes two scripts that automate error-prone steps:

| Script | Purpose | When to use |
|--------|---------|-------------|
| `rename.sh` | Replaces `mcp-hello-world` with your app name across all source and config files | Step 1 of the workflow (immediately after copying the template) |
| `validate.sh` | Runs 28 conformance checks (build, structure, security, customization, endpoints) | Step 3 of the workflow (after implementing tools) |

Always use these scripts rather than running the steps manually.

**CRITICAL:** You must `cd` into the project directory before running `rename.sh`. The script uses `find .` relative to the current directory. Running it from a parent directory will corrupt sibling projects. The script checks for `package.json` and refuses to run if it is not in the current directory.

## Port Conflicts

The dev server runs on port 8080. Before starting:

```bash
lsof -ti:8080 | xargs kill -9 2>/dev/null
sleep 1
npm start
```

If port 8080 is occupied by another MCP server, kill it first. Do not change the port — it must match the k8s service and probe configuration.
