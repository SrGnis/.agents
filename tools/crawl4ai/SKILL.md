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
rendering, anti-bot bypass, and multiple output formats.

---

## Available Tools

| Tool | Purpose |
|------|---------|
| `crawl` | Full web crawling with JS rendering, wait selectors, timeout control |
| `md` | Clean markdown extraction from a page |
| `html` | Raw HTML retrieval from a page |
| `screenshot` | Capture a page as a PNG screenshot |
| `pdf` | Generate a PDF from a page |
| `execute_js` | Run JavaScript on a page and return the result |

---

## When to Use Each Tool

- **User wants to read/summarize a page** → `md`
- **SearXNG `web_url_read` fails or returns empty** → `md` (Crawl4AI renders JS)
- **User wants a screenshot** → `screenshot`
- **User wants a PDF** → `pdf`
- **User wants to extract specific data** → `execute_js` or `crawl`
- **User wants raw HTML** → `html`

---

## md

Fetch a URL and return clean markdown content. This is the primary tool for
reading web pages - it uses a real browser to render JavaScript.

```json
{ "url": "https://example.com/some-article" }
```

Optional parameters:
- `wait_for` — CSS selector to wait for before extracting (e.g. `"css:.content"`)
- `timeout` — Timeout in milliseconds (default: 30000)

---

## screenshot

Capture a full-page screenshot of a URL.

```json
{ "url": "https://example.com" }
```

Optional parameters:
- `full_page` — Capture entire scrollable page (default: true)

---

## pdf

Generate a PDF document from a URL.

```json
{ "url": "https://example.com" }
```

---

## crawl

Full web crawling with advanced options.

```json
{
  "url": "https://example.com",
  "wait_for": "css:.main-content",
  "timeout": 30000
}
```

---

## execute_js

Execute JavaScript on a page and return the result.

```json
{
  "url": "https://example.com",
  "script": "document.title"
}
```

---

## Recommended Workflow

1. **Use SearXNG's `web_url_read` first** — it's faster for simple pages.
2. **If that fails** (empty content, blocked, JS-required) → use `md` from Crawl4AI.
3. **For screenshots/PDFs** → use `screenshot` or `pdf` directly.
4. **For dynamic content** → use `md` with `wait_for` to wait for JS to load.

---

## Tips

- Crawl4AI renders JavaScript, so it can read SPAs and dynamic content.
- Use `wait_for` with CSS selectors to wait for specific elements to load.
- For pages behind Cloudflare or similar, Crawl4AI's browser handles it better.
- The `execute_js` tool can extract data that CSS selectors can't reach.

---

## Error Handling

| Symptom | Fix |
|---------|-----|
| Timeout error | Increase `timeout` or add `wait_for` selector |
| Empty content | Page may require more time to load — increase timeout |
| Connection refused | Check if Crawl4AI container is running (`docker ps`) |
