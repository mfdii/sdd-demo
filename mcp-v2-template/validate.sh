#!/bin/bash

echo "=== SDD Conformance Validation ==="
PASS=0
FAIL=0

check() {
  if eval "$2" > /dev/null 2>&1; then
    echo "  PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $1"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "--- Build ---"
check "TypeScript compiles"          "npm run build"
check "Zero CVEs"                    "npm audit 2>&1 | grep -q '0 vulnerabilities'"

echo ""
echo "--- Structure ---"
check "Containerfile exists"         "test -f Containerfile"
check "No Dockerfile"               "! test -f Dockerfile"
check "package.json type=module"     "grep -q '\"type\": \"module\"' package.json"
check "k8s manifests exist"         "test -f k8s/deployment.yaml && test -f k8s/service.yaml && test -f k8s/route.yaml"
check "k6 load test exists"         "test -f k6/load-test.js"
check "ServiceMonitor exists"       "test -f k8s/servicemonitor.yaml"
check "Dashboard exists"            "test -f k8s/dashboard.yaml"

echo ""
echo "--- Security ---"
check "No axios dependency"          "! grep -q 'axios' package.json"
check "No dotenv dependency"         "! grep -q 'dotenv' package.json"
check "No lodash dependency"         "! grep -q 'lodash' package.json"
check "No eval in source"           "! grep -rq 'eval(' src/"
check "No exec in source"           "! grep -rq 'child_process' src/"
check "Security context in deploy"  "grep -q 'runAsNonRoot: true' k8s/deployment.yaml"
check "Drop ALL caps in deploy"     "grep -q 'drop:' k8s/deployment.yaml"

echo ""
echo "--- Customization ---"
check "App renamed from template"    "! grep -Fq mcp-hello-world package.json"
check "No hello tool in server.ts"   "! grep -Fq \"registerTool('hello'\" src/server.ts"
check "Custom tool registered"       "grep -Fq registerTool src/server.ts"
check "withMetrics wraps tool"       "grep -Fq withMetrics src/server.ts"
check "Description updated"          "! grep -Fq 'Hello world MCP v2 server' package.json"
check "No template refs in source"   "! grep -rFq mcp-hello-world src/"
check "No template refs in k8s"      "! grep -rFq mcp-hello-world k8s/"

echo ""
echo "--- Endpoints ---"
lsof -ti:8080 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1
npm start &
SERVER_PID=$!
sleep 2

check "Health endpoint"              "curl -sf http://localhost:8080/health | grep -q 'ok'"
check "Ready endpoint"               "curl -sf http://localhost:8080/ready | grep -q 'ready'"
check "Metrics endpoint"             "curl -sf http://localhost:8080/metrics | grep -q 'mcp_server_info'"
check "MCP tool call returns result" "curl -sf -X POST http://localhost:8080/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}' | grep -q 'result'"
check "No hello tool in live server" "! curl -sf -X POST http://localhost:8080/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}' | grep -q '\"name\":\"hello\"'"

kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null || true

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ $FAIL -gt 0 ]; then
  echo "CONFORMANCE: FAIL"
  exit 1
else
  echo "CONFORMANCE: PASS"
  exit 0
fi
