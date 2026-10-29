---
name: crawl4ai
description: >
  Read web pages, take screenshots, and generate PDFs using a self-hosted
  Crawl4AI instance via MCP. Use this skill when the user wants to read a URL
  that failed with the SearXNG URL reader, needs JavaScript-rendered content,
  requires screenshots or PDFs, or when dealing with anti-bot protected sites.
  Trigger on phrases like "read this page", "screenshot this", "capture as PDF",
  or when web_url_read returns empty/blocked content.
license: MIT
compatibility: opencode
metadata:
  type: web-scraping
  protocol: mcp
---

# Crawl4AI Web Scraping Skill

Use this skill to read, screenshot, or PDF web pages through the connected
Crawl4AI MCP server. It provides browser-based content extraction with JS
rendering, stealth fingerprint masking, and multiple output formats.

---

## Available Tools

| Tool | Purpose |
|------|---------|
| `crawl` | Full crawl; the only tool accepting `browser_config` / `crawler_config` |
| `md` | Clean markdown extraction (fit / raw / bm25 / llm modes) |
| `html` | Raw HTML retrieval |
| `screenshot` | Capture a page as a PNG (stored server-side as an artifact) |
| `pdf` | Generate a PDF (stored server-side as an artifact) |
| `execute_js` | Run JavaScript on a page — **disabled by default**, see below |

---

## When to Use Each Tool

- **User wants to read/summarize a page** → `md`
- **SearXNG `web_url_read` fails or returns empty** → `md` (Crawl4AI renders JS)
- **User wants a screenshot** → `screenshot`
- **User wants a PDF** → `pdf`
- **User wants raw HTML** → `html`
- **Need custom browser/crawler settings** → `crawl`
- **Need data CSS selectors can't reach** → `execute_js` (if enabled), else `md` with `f: "raw"` and parse the DOM

---

## md

Primary tool for reading web pages.

```json
{ "url": "https://example.com/some-article" }
```

| Param | Type | Default | Notes |
|-------|------|---------|-------|
| `url` | string | required | Absolute http/https URL |
| `f` | `fit` \| `raw` \| `bm25` \| `llm` | `fit` | `fit` = readability extraction; `raw` = full DOM→MD (use for tables/structured data) |
| `q` | string | null | Query string for `bm25` / `llm` filters |
| `c` | string | `"0"` | Cache-bust / revision counter |
| `provider` | string | null | LLM provider override (e.g. `anthropic/claude-3-opus`), only for `f: "llm"` |
| `temperature` | number | null | 0.0–2.0, only for `f: "llm"` |

There is **no `wait_for` or `timeout` param** on `md`. For wait-selector control use `crawl`.

---

## crawl

The only tool exposing browser/crawler tuning. Takes a **list** of URLs.

```json
{
  "urls": ["https://example.com"],
  "browser_config": { "enable_stealth": true },
  "crawler_config": { "wait_time": 2.0 }
}
```

| Param | Type | Notes |
|-------|------|-------|
| `urls` | array | Required. Capped at 100 entries server-side |
| `browser_config` | object | `BrowserConfig` fields |
| `crawler_config` | object | `CrawlerRunConfig` fields |
| `crawler_configs` | array | Per-URL configs for `arun_many()`, supports `url_matcher` |
| `hooks` | object | Requires `CRAWL4AI_HOOKS_ENABLED=true` (RCE risk, off by default) |

### Useful `browser_config` fields

`enable_stealth`, `user_agent_mode` (`"random"`), `user_agent`, `headless`,
`browser_type`, `viewport_width`, `viewport_height`, `locale`, `timezone_id`,
`session_id`, `light_mode`, `text_mode`, `java_script_enabled`,
`ignore_https_errors`, `verbose`, `use_managed_browser`.

### Useful `crawler_config` fields

`wait_for`, `wait_time`, `delay_before_return_html`, `page_timeout`,
`word_count_threshold`, `target_elements`, `remove_selectors`,
`exclude_external_links`, `exclude_social_media_links`, `process_iframes`,
`scan_full_page`, `cache_mode`, `stream`, `log_console`, `screenshot`, `pdf`,
`markdown_generator`, `scraping_strategy`, `extraction_strategy`, `locale`,
`timezone_id`, `user_agent`.

### Blocked fields (untrusted request boundary)

The server rejects these with `Rejected config: field … is not permitted on …
from an untrusted request`:

- `browser_config`: `user_data_dir`, `proxy`, `headers`
- `crawler_config`: `magic`, `simulate_user`, `deep_crawl_strategy`, `js_code`

`simulate_user` is already forced on via `crawler.base_config`, so blocking it is
intentional. `proxy` / `headers` / `user_data_dir` are SSRF and auth-exfil
vectors; `js_code` and `deep_crawl_strategy` are RCE / DoS vectors.

---

## screenshot

```json
{ "url": "https://example.com" }
```

| Param | Type | Notes |
|-------|------|-------|
| `url` | string | Required |
| `screenshot_wait_for` | number | Seconds to wait before capture (default 2) |
| `wait_for_images` | boolean | Default false |
| `output_path` | string | **Deprecated and ignored** since 0.9.0. Result is returned as an artifact with `artifact_id` + `url` |

---

## pdf

```json
{ "url": "https://example.com" }
```

`output_path` is deprecated and ignored — same artifact mechanism as `screenshot`.

---

## execute_js

```json
{ "url": "https://example.com", "scripts": ["document.title"] }
```

`scripts` is a **list** of snippets run in order (singular `script` is wrong).

**Disabled by default.** The endpoint returns `execute_js endpoint is disabled.
Set CRAWL4AI_EXECUTE_JS_ENABLED=true to enable.` — enable it in the container
env only if you accept the RCE surface.

There is no request-side substitute: `crawler_config.js_code` is on the
blocklist. Without the env var, use `md` with `f: "raw"` and parse the DOM, or
`crawl` with `crawler_config.wait_for` to wait for JS-rendered nodes to appear.

---

## Defaults already applied server-side

`config.yml` → `crawler.browser.kwargs` is passed to `BrowserConfig` by `/md`,
`/html`, `/screenshot`, `/pdf` and `/ask`:

```yaml
headless: true
text_mode: true              # images/fonts/media are blocked at the network layer
enable_stealth: true         # strips navigator.webdriver, patches fingerprints
user_agent_mode: "random"    # realistic UA pool instead of the stale Chrome/116 default
viewport_width: 1920
viewport_height: 1080
```

Verified against `bot.sannysoft.com`: `WebDriver: missing (passed)`, Chrome/135 UA,
`Plugins Length: 3`, `Languages: en-US,en`, no failed tests.

### `crawl` does NOT inherit those defaults

`/crawl` builds its browser from the **request's** `browser_config`
(`api.py`: `BrowserConfig.load(browser_config, provenance=UNTRUSTED)`). It never
reads `crawler.browser.kwargs`, so omitting `browser_config` falls back to the
library default — stale `Chrome/116`, no stealth, 1080×600.

Always pass the stealth block explicitly on `crawl`:

```json
{
  "urls": ["https://example.com"],
  "browser_config": {
    "enable_stealth": true,
    "user_agent_mode": "random",
    "viewport_width": 1920,
    "viewport_height": 1080
  }
}
```

`crawler.base_config` (currently `simulate_user: true`) *is* merged into every
`/crawl` `crawler_config`, so that one carries over.

Two known residual tells: no WebGL context (from `--disable-gpu` /
`--disable-software-rasterizer` in `browser.extra_args`) and `headless: true`.

---

## Recommended Workflow

1. **Use SearXNG's `web_url_read` first** — it's faster for simple pages.
2. **If that fails** (empty content, blocked, JS-required) → use `md`.
3. **For tables/structured pages** → `md` with `f: "raw"`.
4. **For screenshots/PDFs** → `screenshot` or `pdf`.
5. **For custom waits or browser tuning** → `crawl` with `crawler_config`.

---

## Error Handling

| Symptom | Fix |
|---------|-----|
| `Rejected config: field 'X' is not permitted` | Field is on the untrusted blocklist — see above |
| `execute_js endpoint is disabled` | Expected. Use `md` `f: "raw"` + parse, or `crawl` + `wait_for`. `crawler_config.js_code` is blocklisted — only `CRAWL4AI_EXECUTE_JS_ENABLED=true` enables JS |
| Timeout error | Raise `crawler_config.page_timeout` or add `wait_for` via `crawl` |
| Empty content | Page needs more time — use `crawl` with `wait_time` / `delay_before_return_html` |
| Connection refused | Check the container (`docker ps`) — see `tools/crawl4ai/README.md` |
| Images missing in `screenshot`/`pdf` | Expected: `text_mode: true` blocks image/font/media requests. Image *URLs* still appear in `media.images`. Set `browser_config.text_mode: false` via `crawl` to render them |
| Stale config after editing `config.yml` | `load_config()` re-reads per request, but a bind-mounted file replaced by a new inode can go stale — `docker compose up -d --force-recreate` |
