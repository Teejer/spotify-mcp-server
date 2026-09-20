# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Build stage — compiles the TypeScript MCP server
# ---------------------------------------------------------------------------
FROM node:26-alpine AS build
WORKDIR /app

# Install all dependencies first (better layer caching)
COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

# ---------------------------------------------------------------------------
# Runtime stage
# ---------------------------------------------------------------------------
FROM node:26-alpine
ENV NODE_ENV=production
WORKDIR /app

# Supergateway bridges the server's stdio MCP transport to Streamable HTTP
# (and SSE/WS), so the container can actually "serve" the server over a port.
RUN npm install -g supergateway@^4.0.0 && npm cache clean --force

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/build ./build
COPY package.json ./

# NOTE: spotify-config.json is deliberately NOT copied into the image — it
# holds OAuth credentials. Bind-mount it at runtime instead (see compose file).
# The server rewrites this file when it refreshes Spotify tokens, so the
# mount must be read-write.

EXPOSE 8080

# Serve the MCP server over Streamable HTTP at http://localhost:8080/mcp
# ("--stateful" keeps one stdio server process alive per client session).
CMD ["supergateway", \
  "--stdio", "node /app/build/index.js", \
  "--outputTransport", "streamableHttp", \
  "--stateful", \
  "--sessionTimeout", "600000", \
  "--port", "8080"]
