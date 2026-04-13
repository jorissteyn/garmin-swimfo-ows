FROM node:22-alpine

WORKDIR /app/server
COPY server/package.json server/package-lock.json* ./
RUN npm ci --omit=dev --no-audit --no-fund || npm install --omit=dev --no-audit --no-fund

COPY server/ ./

EXPOSE 31415
CMD ["node", "index.js"]
