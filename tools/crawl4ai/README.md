# Crawl4AI Tool

Self-hosted web scraping and content extraction using [Crawl4AI](https://github.com/unclecode/crawl4ai).

## What It Does

- Reads web pages with full JavaScript rendering (handles SPAs, dynamic content)
- Captures screenshots and generates PDFs
- Executes JavaScript on pages for custom data extraction
- Bypasses anti-bot protection using a real browser

## Architecture

```
OpenCode ──stdio──► crawl4ai-mcp (npm) ──HTTP──► Crawl4AI Docker (port 11235)
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Crawl4AI container configuration |
| `.env` | Environment variables (version, port) |
| `install.sh` | Installs Docker container + npm MCP server + configures harnesses |
| `uninstall.sh` | Removes Docker container + npm MCP server + harness integrations |
| `SKILL.md` | AI agent skill documentation |
| `opencode/` | OpenCode harness adapter scripts |

## Manual Usage

```bash
# Start the container
docker compose up -d

# Test the API
curl http://localhost:11235/health

# Stop the container
docker compose down
```

## Configuration

Edit `.env` to change settings:

```bash
# Crawl4AI version
CRAWL4AI_VERSION=latest

# Port to expose
CRAWL4AI_PORT=11235
```

## Dependencies

- Docker
- pnpm (for global npm package installation)
