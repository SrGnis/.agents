# Global Agent Rules

Rules that apply to all agents and all projects.

## Code Style

- Be concise. Short answers, no preamble or postamble.
- Never add comments unless explicitly asked.
- Follow existing code conventions — read neighboring files before writing.
- Always prefer editing existing files over creating new ones.
- Use `file_path:line_number` format when referencing code locations.

## Security

- Never expose secrets, API keys, or tokens in output or code.
- Never commit secrets or keys to a repository.
- Use environment variables or `{env:VAR}` interpolation for sensitive values.

## Verification

- After making code changes, run lint and typecheck commands if available (e.g., `npm run lint`, `npm run typecheck`, `ruff`).
- If you don't know the command, ask the user. Suggest adding it to `AGENTS.md` for future reference.

## Git

- Only commit, push, or create PRs when explicitly asked.
- Before committing, inspect `git status`, `git diff`, and recent `git log`.
- Stage only intended files. Never commit secrets.
- Write commit messages that match the repo's existing style.

## Tool Usage

### Web Search: SearXNG (preferred)

Use SearXNG as the primary tool for web search and URL reading.

| Tool | When to use |
|------|-------------|
| `searxng_web_search` | Searching for information, docs, news, discussions |
| `web_url_read` | Reading a specific URL the user provides or a search result |
| `searxng_search_suggestions` | Refining vague or partial queries before searching |
| `searxng_instance_info` | Checking available categories/engines if a search fails |

**Tips:**
- Use specific queries: `"Python asyncio vs trio 2024"` beats `"async python"`.
- Filter by category for tech topics: `categories: "it"`.
- Use `time_range` for recent results: `"day"`, `"week"`, `"month"`.
- Always summarize findings — never paste large raw search output.
- Respect copyright: paraphrase, don't reproduce verbatim excerpts.

### Web Scraping: Crawl4AI (fallback)

Use Crawl4AI when SearXNG fails or for advanced web tasks.

| Tool | When to use |
|------|-------------|
| `md` | SearXNG returned empty/blocked content, or page requires JavaScript |
| `screenshot` | User wants a screenshot of a page |
| `pdf` | User wants a PDF capture of a page |
| `execute_js` | Extracting data that CSS selectors can't reach |
| `html` | Raw HTML is needed |
| `crawl` | Full crawl with advanced options (wait selectors, timeouts) |

**Tips:**
- Crawl4AI renders JavaScript — use it for SPAs and dynamic content.
- Use `wait_for` with a CSS selector to wait for elements to load.
- It handles anti-bot protection (Cloudflare, etc.) via real browser.
- For clean results, use `md`. For raw data, use `html` or `execute_js`.

### Workflow

1. **Search** → Use `searxng_web_search`
2. **Read a URL** → Use `web_url_read`
3. **If URL fails** (empty, blocked, JS-required) → Use `md` from Crawl4AI
4. **Screenshots/PDFs** → Use Crawl4AI `screenshot` or `pdf` directly
5. **Dynamic content** → Use Crawl4AI `md` with `wait_for` selector

### Architecture Documentation: arc42

arc42 skills are available for documenting software architecture:

- **Sections 1-12** — Interactive guided documentation for each arc42 section
- **arc42-review** — Review sections for completeness and consistency
- **arc42-lint** — Validate cross-section ID consistency

Use when the user wants to create or review architecture documentation following the arc42 template.

### Code Indexing: Qdrant

Semantic search over codebases using vector embeddings and tree-sitter parsing.

| Tool | When to use |
|------|-------------|
| `qdrant-find` | Searching for code by natural language description |
| `/index` | Index/re-index the codebase or install git hooks |

**How it works:**
- Git hooks (`post-commit`, `post-checkout`) automatically index changed files
- Each branch is indexed separately — search results reflect the current branch
- Git blob hashes prevent duplicate entries across branches
- Uses tree-sitter for AST-aware code parsing (functions, classes, methods)

**When to use Qdrant vs grep:**

| Scenario | Best tool |
|----------|-----------|
| "How does X work?" (open-ended) | `qdrant-find` first, then `grep` for details |
| "Where is function `foo` defined?" | `grep` |
| "Find code that does Y" (no exact name) | `qdrant-find` |
| "Which files import Z?" | `grep` |
| Exploring an unfamiliar codebase | `qdrant-find` for overview |

**Workflow for exploring features:**
1. Start with `qdrant-find` using a natural language query about the feature
2. Review returned snippets to identify key files and function names
3. Use `grep` to find related scopes, helpers, or exact locations
4. Use `read` to get full context of specific files

**Tips:**
- Use natural language: "how is authentication implemented" not "auth function"
- Describe what code does, not how it's written
- Run `/index` after cloning a repo to install hooks and do initial index
- The index is per-branch — switch branches and search context changes
- Code is indexed on commit — uncommitted changes may not appear
- Qdrant results include file paths and line numbers — use them to navigate directly
