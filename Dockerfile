# ── Build stage: install all deps + compile TypeScript ────────
FROM node:22-alpine AS builder

WORKDIR /app/server
COPY server/package.json server/package-lock.json* ./
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund

COPY server/tsconfig.json ./
COPY server/src ./src
RUN npm run build

# ── Runtime stage: prod deps + compiled JS only ───────────────
FROM node:22-alpine

WORKDIR /app/server
COPY server/package.json server/package-lock.json* ./
RUN npm ci --omit=dev --no-audit --no-fund || npm install --omit=dev --no-audit --no-fund

COPY --from=builder /app/server/dist ./dist

EXPOSE 31415
CMD ["node", "dist/index.js"]
