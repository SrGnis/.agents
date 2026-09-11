# SearXNG Tool

Self-hosted SearXNG search engine with MCP server integration.

## Setup

```bash
# From the agents root
./setup.sh
```

This will:
1. Start SearXNG containers via Docker Compose
2. Install `mcp-searxng` globally via pnpm
3. Detect installed coding-agent harnesses
4. Prompt you to select harnesses to configure
5. Run each selected harness adapter

## Harness Integrations

Harness adapters live inside the tool directory:

```text
searxng/
  install.sh
  uninstall.sh
  opencode/
    detect.sh
    install.sh
    uninstall.sh
```

The OpenCode adapter is selected when the `opencode` command or an OpenCode
configuration file is present. It registers the MCP server in
`~/.config/opencode/opencode.jsonc` (or `opencode.json` if that file exists).
Restart OpenCode after setup to load the new MCP server.

To add another harness, create a directory with `detect.sh`, `install.sh`, and
`uninstall.sh`. The shared installer will discover it without changes to the
root setup script.

The generated OpenCode configuration is:

```json
{
  "mcp": {
    "searxng": {
      "type": "local",
      "command": ["npx", "-y", "mcp-searxng"],
      "enabled": true,
      "environment": {
        "SEARXNG_URL": "http://localhost:8888"
      }
    }
  }
}
```

> Adjust `SEARXNG_URL` to match the port in your `.env` file (default: `8888`).

## Configuration

Edit `.env` to change the port or version:

```bash
SEARXNG_VERSION=latest
SEARXNG_HOST=[::]
SEARXNG_PORT=8888
```

Then restart:
```bash
docker compose down && docker compose up -d
```

## Disable

Set `SEARXNG_ENABLED=false` in `config.env` and run `./setup.sh` to stop containers, uninstall the MCP server, and remove the skill symlink.
