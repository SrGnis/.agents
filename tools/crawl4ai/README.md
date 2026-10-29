# Crawl4AI Tool

Self-hosted web scraping and content extraction using [Crawl4AI](https://github.com/unclecode/crawl4ai).

## What It Does

- Reads web pages with full JavaScript rendering (handles SPAs, dynamic content)
- Captures screenshots and generates PDFs
- Masks automation fingerprints (stealth mode) and rotates user agents
- Bypasses basic anti-bot protection using a real browser

`execute_js` is disabled by default (see [Disabled features](#disabled-features)).

## Architecture

```
OpenCode ──stdio──► crawl4ai-mcp (npm) ──HTTP──► Crawl4AI Docker (port 11235)
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Crawl4AI container configuration |
| `config.yml` | Crawl4AI app config, bind-mounted over `/app/config.yml` |
| `.env` | Environment variables (version, port, API token) |
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

### Environment (`.env`)

```bash
CRAWL4AI_VERSION=latest     # image tag
CRAWL4AI_PORT=11235         # host port
CRAWL4AI_API_TOKEN=...      # required; the auth guard refuses an open bind without it
```

### Application (`config.yml`)

Mounted read-only at `/app/config.yml`. The image's path is hardcoded
(`utils.py: load_config()` → `Path(__file__).parent / "config.yml"`), so the
mount is the only way to override it without rebuilding.

`crawler.browser.kwargs` is passed to `BrowserConfig` for `/md`, `/html`,
`/screenshot`, `/pdf` and `/ask`. `crawler.base_config` is merged into every
`/crawl` `crawler_config`. Note that `/crawl` builds its browser from the
**request's** `browser_config` and does not inherit `crawler.browser.kwargs` —
callers that need stealth on `/crawl` must pass it explicitly.

Current overrides (everything else is the image's hardened default):

```yaml
crawler:
  browser:
    kwargs:
      headless: true
      text_mode: true              # blocks image/font/media requests at the network layer
      enable_stealth: true         # strips navigator.webdriver, patches fingerprints
      user_agent_mode: "random"    # realistic UA pool instead of stale Chrome/116
      viewport_width: 1920
      viewport_height: 1080
```

Verified against `bot.sannysoft.com`: `WebDriver: missing (passed)`, Chrome/135
UA, `Plugins Length: 3`, `Languages: en-US,en`, no failed tests.

`load_config()` re-reads `config.yml` on every request, so edits apply without a
restart. Caveat: if your editor replaces the file (new inode) rather than
writing in place, the bind mount keeps serving the old one — run
`docker compose up -d --force-recreate` if a change seems ignored.

### Trust boundary

`crawl` is the only tool accepting `browser_config` / `crawler_config`, and the
server rejects privileged fields with `Rejected request: field … is not
permitted on … from an untrusted request`:

| Blocklist | Fields | Why |
|-----------|--------|-----|
| `browser_config` | `user_data_dir`, `proxy`, `headers` | SSRF, egress escape, auth exfil |
| `crawler_config` | `magic`, `simulate_user`, `deep_crawl_strategy`, `js_code` | forced server-side / RCE / DoS |

`simulate_user: true` is already set in `crawler.base_config`, which is why it is
not request-settable. Per-request values still win over `base_config` for any
field that is not blocklisted.

### Security notes

The image default for `browser.extra_args` deliberately excludes
`--disable-web-security`, `--allow-insecure-localhost` and
`--ignore-certificate-errors` — do not re-add them, they disable TLS
verification for every crawl. `--no-sandbox` must stay while the container runs
non-root without a usable sandbox; remove it only behind an unprivileged user
namespace or a verified seccomp profile.

## Disabled features

| Feature | Gate | Enabling |
|---------|------|----------|
| `execute_js` | `CRAWL4AI_EXECUTE_JS_ENABLED=true` | Container env. **RCE surface** — note `crawler_config.js_code` is also blocklisted, so this env var is the only path to JS execution |
| Hooks | `CRAWL4AI_HOOKS_ENABLED=true` | Container env. **RCE surface** |
| Insecure TLS | `CRAWL4AI_ALLOW_INSECURE_TLS=true` | Container env. Trusted internal testing only |

## Dependencies

- Docker
- pnpm (for global npm package installation)
