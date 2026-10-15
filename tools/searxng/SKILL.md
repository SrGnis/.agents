---
name: searxng
description: >
  Search the web and read URLs using a self-hosted SearXNG instance via MCP.
  Use this skill whenever the user wants to search for information online, look
  something up, find recent news, research a topic, or read the contents of a
  URL. Prefer this over other search approaches when the SearXNG MCP server is
  available. Trigger on any phrase like "search for", "look up", "find info on",
  "what is the latest on", "read this URL", "summarize this page", or whenever
  current/external information is needed.
license: MIT
compatibility: opencode
metadata:
  type: search
  protocol: mcp
---

# SearXNG Web Search Skill

Use this skill to search the web or fetch URL content through the connected
SearXNG MCP server. It provides private, self-hosted search with filtering,
pagination, and URL reading.

---

## Available Tools

| Tool | Purpose |
|------|---------|
| `searxng_web_search` | Run a web search with optional filters |
| `searxng_search_suggestions` | Get autocomplete suggestions to refine a query |
| `searxng_instance_info` | Discover available categories, engines, and defaults |
| `web_url_read` | Fetch a URL and return its content as markdown |

---

## When to Use Each Tool

- **Searching for information** → `searxng_web_search`
- **Query is vague or misspelled** → `searxng_search_suggestions` first, then search
- **User gives a URL to read or summarize** → `web_url_read`
- **Unsure which categories/engines are available** → `searxng_instance_info`

---

## searxng_web_search

### Required
- `query` (string) — The search query

### Optional filters
| Parameter | Type | Description |
|-----------|------|-------------|
| `categories` | string | Comma-separated: `general`, `it`, `science`, `news`, `images`, `videos`, `social_media` |
| `language` | string | e.g. `en`, `es`, `fr`, `de` |
| `time_range` | string | `day`, `week`, `month`, `year` |
| `safesearch` | integer | `0` = off, `1` = moderate, `2` = strict |
| `num_results` | integer | Number of results (default: 10, max: 20) |
| `page` | integer | Page number for pagination (default: 1) |

### Example calls

**Basic search:**
```json
{ "query": "rust async runtime comparison 2024" }
```

**Tech topic, recent, in English:**
```json
{
  "query": "WebAssembly in production",
  "language": "en",
  "time_range": "month",
  "num_results": 10
}
```

**News search:**
```json
{
  "query": "AI regulation Europe",
  "categories": "news",
  "time_range": "week"
}
```

**Paginate for more results:**
```json
{ "query": "open source LLM benchmarks", "page": 2 }
```

---

## web_url_read

Fetches a URL and returns its content as markdown. Use when the user shares a
link, or when a search result looks promising and you want to read it in full.

```json
{ "url": "https://example.com/some-article" }
```

Optional parameters:
- `page` — For paginated long content (default: 1)
- `section` — Target a specific section heading if known

---

## searxng_search_suggestions

Use to refine or autocomplete an ambiguous query before searching.

```json
{ "query": "how to deploy" }
```

Returns a list of suggested completions. Pick the most relevant one and pass it
to `searxng_web_search`.

---

## searxng_instance_info

Call this if you're unsure which categories or engines the instance supports,
or if a search fails due to an unsupported category.

```json
{ "includeEngines": true }
```

---

## Recommended Workflow

1. **Clarify the query** if it's vague — use `searxng_search_suggestions` or
   ask the user.
2. **Run `searxng_web_search`** with appropriate filters.
3. **Evaluate results** — check titles, URLs, and snippets.
4. **Fetch promising pages** with `web_url_read` if deeper content is needed.
5. **Paginate** (`page: 2`, `page: 3`) if the first page doesn't yield enough.
6. **Synthesize** — summarize findings in your own words; never paste large
   blocks of raw search output at the user.

---

## Tips

- Prefer **specific queries** over vague ones: `"Python asyncio vs trio performance 2024"` beats `"async python"`.
- **Avoid `categories: "it"` for general searches** — it excludes Google/Bing/DuckDuckGo and only searches package registries, code hosting, and Docker Hub. Use it only when you specifically want npm/pypi/packagist results. For general library/framework searches, omit the category filter.
- For **current events**, use `time_range: "week"` or `"day"` with `categories: "news"`.
- If a search returns poor results, try **rephrasing** or calling `searxng_search_suggestions`.
- When reading a URL, if content is truncated, increment `page` to get the rest.
- Respect **copyright**: summarize and paraphrase content from URLs; do not reproduce large verbatim excerpts.

---

## Error Handling

| Symptom | Fix |
|--------|-----|
| No results | Broaden the query, remove filters, or try page 2 |
| Category not found | Call `searxng_instance_info` to check supported categories |
| URL fetch fails | Try a different result from the search; note the failure to the user |
| JSON parse error | The instance may not have JSON format enabled — ask the user to verify `settings.yml` |
