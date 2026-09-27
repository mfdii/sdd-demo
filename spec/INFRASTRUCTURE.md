# Infrastructure Specification

## Platform

- **OpenShift**: 4.22 (Kubernetes 1.35)
- **Build strategy**: Source-to-Image via BuildConfig with Docker strategy
- **Registry**: Internal OpenShift registry via ImageStream
- **Monitoring**: OpenShift user-workload monitoring (Prometheus Operator)
- **Dashboards**: Perses (OpenShift Cluster Observability Operator)

## Container Image

### Base Images

| Stage | Image | Purpose |
|-------|-------|---------|
| Builder | `registry.access.redhat.com/hi/nodejs:26-builder` | npm install + tsc compile |
| Deps | `registry.access.redhat.com/hi/nodejs:26-builder` | Production npm install (separate layer for caching) |
| Runtime | `registry.access.redhat.com/hi/nodejs:26` | Hummingbird distroless runtime |

These are the only approved base images. Do not use `node:`, `alpine`, `ubi`, or any other base.

The runtime image is **distroless** — no shell, no package manager, no system utilities. This means:
- All dependencies must be pure JavaScript (no native/C++ compilation)
- No `apt-get`, `apk`, or `yum` in the Containerfile
- No `RUN` commands in the runtime stage
- Debugging on the pod uses `oc exec -- node -e "..."` (Node.js is the only binary)

### Containerfile

The file is named `Containerfile` (NOT `Dockerfile`). It uses a 3-stage build:

```dockerfile
FROM registry.access.redhat.com/hi/nodejs:26-builder AS builder
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm ci
COPY src ./src
RUN npm run build

FROM registry.access.redhat.com/hi/nodejs:26-builder AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

FROM registry.access.redhat.com/hi/nodejs:26
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./
EXPOSE 8080
ENV PORT=8080 NODE_ENV=production
CMD ["node", "dist/server.js"]
```

Why 3 stages:
1. **builder** — Installs all deps (including devDeps) and compiles TypeScript
2. **deps** — Clean install of production-only deps (avoids `npm prune` permission issues on Hummingbird)
3. **runtime** — Distroless image with only compiled JS and production node_modules

## Kubernetes Manifests

All manifests live in `k8s/`. Plain YAML only — no Helm, no Kustomize, no jsonnet.

Replace `{{APP_NAME}}` with your server's kebab-case name in every manifest.

### k8s/imagestream.yaml

```yaml
---
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: {{APP_NAME}}
  labels:
    app: {{APP_NAME}}
```

### k8s/buildconfig.yaml

```yaml
---
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: {{APP_NAME}}
  labels:
    app: {{APP_NAME}}
spec:
  output:
    to:
      kind: ImageStreamTag
      name: {{APP_NAME}}:latest
  source:
    type: Git
    git:
      uri: {{GIT_REPO_URL}}
      ref: main
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Containerfile
  triggers:
  - type: ConfigChange
```

Key points:
- `dockerfilePath: Containerfile` — must match the actual file name
- `ref: main` — change to your branch if needed
- `ConfigChange` trigger starts a build when the BuildConfig is created or updated
- To start a manual build: `oc start-build {{APP_NAME}}`

### k8s/deployment.yaml

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{APP_NAME}}
  labels:
    app: {{APP_NAME}}
  annotations:
    image.openshift.io/triggers: >-
      [{"from":{"kind":"ImageStreamTag","name":"{{APP_NAME}}:latest"},
        "fieldPath":"spec.template.spec.containers[?(@.name==\"{{APP_NAME}}\")].image"}]
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {{APP_NAME}}
  template:
    metadata:
      labels:
        app: {{APP_NAME}}
    spec:
      containers:
      - name: {{APP_NAME}}
        image: " "
        ports:
        - containerPort: 8080
          protocol: TCP
        env:
        - name: PORT
          value: "8080"
        - name: NODE_ENV
          value: production
        - name: TZ
          value: UTC
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
        startupProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          failureThreshold: 12
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: [ALL]
          runAsNonRoot: true
          seccompProfile:
            type: RuntimeDefault
```

Key points:
- `image: " "` — intentionally blank; the ImageStream trigger annotation fills it
- The `image.openshift.io/triggers` annotation auto-updates the image when a new build completes
- The container name in the annotation `fieldPath` must match `containers[].name`
- Resource defaults are for lightweight API-wrapping servers. Increase limits for servers with ML models or heavy processing.
- Startup probe gives up to 60s for the server to start (12 failures × 5s period)

### k8s/service.yaml

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: {{APP_NAME}}
  labels:
    app: {{APP_NAME}}
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    app: {{APP_NAME}}
  type: ClusterIP
```

The port name `http` is referenced by the ServiceMonitor and Route.

### k8s/route.yaml

```yaml
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: {{APP_NAME}}
  labels:
    app: {{APP_NAME}}
spec:
  port:
    targetPort: http
  tls:
    insecureEdgeTerminationPolicy: Allow
    termination: edge
  to:
    kind: Service
    name: {{APP_NAME}}
    weight: 100
  wildcardPolicy: None
```

### k8s/servicemonitor.yaml

See [OBSERVABILITY.md](OBSERVABILITY.md) for details.

### k8s/dashboard.yaml

See [OBSERVABILITY.md](OBSERVABILITY.md) for details.

## Deployment Commands

### First-time deployment (in order)

```bash
NAMESPACE=<your-namespace>
APP_NAME=<your-app-name>

# 1. Create ImageStream (must exist before BuildConfig)
oc apply -f k8s/imagestream.yaml -n $NAMESPACE

# 2. Create BuildConfig (triggers first build automatically)
oc apply -f k8s/buildconfig.yaml -n $NAMESPACE

# 3. Watch the build
oc logs -f bc/$APP_NAME -n $NAMESPACE

# 4. Once build completes, deploy
oc apply -f k8s/deployment.yaml -n $NAMESPACE
oc apply -f k8s/service.yaml -n $NAMESPACE
oc apply -f k8s/route.yaml -n $NAMESPACE

# 5. Enable monitoring
oc apply -f k8s/servicemonitor.yaml -n $NAMESPACE

# 6. Deploy dashboard (different namespace)
oc apply -f k8s/dashboard.yaml -n openshift-cluster-observability-operator

# 7. Verify
oc get pods -l app=$APP_NAME -n $NAMESPACE
oc get route $APP_NAME -n $NAMESPACE
```

### Subsequent deployments

```bash
# Push code, then start a new build
oc start-build $APP_NAME -n $NAMESPACE

# The ImageStream trigger auto-rolls the Deployment when the build completes
```

### Adding environment variables

For secrets (API keys, database passwords):

```bash
# Create a secret
oc create secret generic $APP_NAME-config \
  --from-literal=API_KEY=your-key \
  --from-literal=DB_PASSWORD=your-password \
  -n $NAMESPACE
```

Then add to deployment.yaml:

```yaml
env:
- name: API_KEY
  valueFrom:
    secretKeyRef:
      name: {{APP_NAME}}-config
      key: API_KEY
```

Never put secrets directly in manifests or code.
