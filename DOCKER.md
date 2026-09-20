# Running in Docker

The Spotify MCP server speaks MCP over **stdio** only, so the image bundles
[Supergateway](https://github.com/supercorp-ai/supergateway), which re-serves it
as a network service. The image supports two ways of consuming the server.

## 1. One-time: Spotify credentials

Create `spotify-config.json` in this directory (already copied from the example
if you followed the setup) and fill in the app credentials from the
[Spotify Developer Dashboard](https://developer.spotify.com/dashboard/) —
with a redirect URI of `http://127.0.0.1:8888/callback` registered on the app.

**Never put this file in the image** — it is bind-mounted at runtime, and the
server writes refreshed OAuth tokens back into it.

Then obtain OAuth tokens (one-time). Either on the host, since Node ≥ 26 is
already installed:

```bash
npm ci
npm run auth        # opens the browser, tokens are saved into spotify-config.json
```

…or entirely inside Docker (prints an authorization URL; authorize in your
browser, then paste the full `http://127.0.0.1:8888/callback?...` URL from the
browser's address bar back into the terminal — it doesn't matter if the page
itself fails to load):

```bash
docker build -t spotify-mcp-server .
docker run -it --rm \
  -v "$PWD/spotify-config.json:/app/spotify-config.json" \
  spotify-mcp-server node /app/build/auth.js
```

On Linux you can add `--network host` so the callback is captured
automatically. After this, token refreshes happen inside the running server —
no browser needed again until the refresh token expires (~6 months).

## 2. Serve over Streamable HTTP (main use)

```bash
docker compose up -d --build
```

The MCP endpoint is then **`http://localhost:8080/mcp`**.

Point any MCP client at that URL, e.g. OpenCode:

```json
{
  "mcp": {
    "spotify": {
      "type": "remote",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

…or Claude Desktop / any client with a `url`-style MCP config:

```json
{
  "mcpServers": {
    "spotify": { "url": "http://localhost:8080/mcp" }
  }
}
```

> The gateway has **no authentication** — keep port 8080 on localhost/trusted
> networks, or put a reverse proxy with auth in front of it.

## 3. Or consume via `docker run -i` (classic stdio)

Clients that launch servers as commands (Claude Desktop, Cursor, Cline) can run
the container directly instead of using the HTTP port:

```json
{
  "mcpServers": {
    "spotify": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-v", "/ABSOLUTE/PATH/spotify-config.json:/app/spotify-config.json",
        "spotify-mcp-server",
        "node", "/app/build/index.js"
      ]
    }
  }
}
```

## Useful commands

```bash
docker compose up -d --build      # build + run (HTTP mode)
docker compose logs -f            # gateway/server logs
docker compose down               # stop

# Change the served port: edit 'ports' in docker-compose.yml,
# e.g. "9000:8080" keeps the container port and serves on host 9000.

# SSE instead of Streamable HTTP: override the command, e.g. in compose:
#   command: ["supergateway", "--stdio", "node /app/build/index.js", "--port", "8080"]
# (endpoint becomes http://localhost:8080/sse)
```

## Troubleshooting

- **`Spotify configuration file not found at /app/spotify-config.json`** — the
  config wasn't mounted (check the volume path in `docker-compose.yml`), or the
  bind-mount turned into a directory because the file didn't exist before
  `docker compose up`. Fix: `docker compose down && rmdir spotify-config.json
  && cp spotify-config.example.json spotify-config.json`, fill in credentials,
  then `docker compose up -d`.
- **`Failed to refresh access token ... invalid_grant`** — the refresh token
  expired or was revoked; re-run `npm run auth` (host or Docker, see above).
- **Config write permission errors on Linux** when switching the container to a
  non-root `user:` — make sure the chosen uid owns `spotify-config.json`.
