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
