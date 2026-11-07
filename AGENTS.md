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
- **Instrument before you fix what you cannot reproduce.** If a bug report is layout-, environment-, hardware- or machine-specific, add a trace at the pipeline boundary and get one run of it. Do not guess twice. If the trace contradicts your theory, the trace is right.
- **A test can assert the bug.** Before changing a formula, a wire format, or a default, grep the test tree for the value you are about to change. A golden written from a passing run certifies the defect and keeps it alive through every green suite.
- **Prove a new test can fail.** Revert the fix and watch it go red before trusting it. A test that passes both ways is vacuous and will be cited as coverage later. Harvest expected values by temporarily failing with the actual value, never from a passing run's internals.
- **Verify what landed before claiming it.** Check `git status` and `git diff --stat` before writing a commit message. A green local build says nothing about commit completeness — the files are still on disk — and a silently failing edit makes the message a lie.
- **Scripted edits silently no-op; verify each one landed.** Multi-line `sed` patterns match nothing across line breaks, and a no-op `sed`/`str_replace` exits zero — the edit looks done and the bug "fixes" nothing. Use the edit tool or a python script with exact strings for anything beyond one line, then grep the result before moving on. (Cost three debugging rounds in one session.)
- **Fetch the tagged source before reverse-engineering third-party internals.** Decompiling a jar or reading bytecode traces is a last resort: `https://raw.githubusercontent.com/<org>/<repo>/<tag>/<path>` answers the question in one read. An hour of bytecode forensics dissolved into one file fetch when the habit was applied.
- **A surviving mutation means the test is wrong, not the mutation.** When a mutation fails to turn a test red, the test is vacuous — stale object copies captured before the action, index-based assertions that coincide with the expected order, goldens with self-perpetuating arithmetic. Fix the test until every mutation bites, and write assertions against identity/labels rather than list indices.

## Git

- Only commit, push, or create PRs when explicitly asked.
- Before committing, inspect `git status`, `git diff`, and recent `git log`.
- Stage only intended files. Never commit secrets.
- Write commit messages that match the repo's existing style.

## Tool Usage

Quick index — per-tool details live in the corresponding skill (loaded on demand).

### Web Search: SearXNG (preferred)

Use SearXNG as the primary tool for web search and URL reading. See the `searxng` skill.

| Tool | When to use |
|------|-------------|
| `searxng_web_search` | Searching for information, docs, news, discussions |
| `web_url_read` | Reading a specific URL the user provides or a search result |
| `searxng_search_suggestions` | Refining vague or partial queries before searching |
| `searxng_instance_info` | Checking available categories/engines if a search fails |

Avoid `categories: "it"` except for package-registry searches — it excludes general search engines.

| SearXNG excels at | SearXNG struggles with |
|-------------------|------------------------|
| Fresh 2026 blog content | Official documentation (kubernetes.io, pkg.go.dev) |
| Privacy (self-hosted, no tracking) | GitHub repos and code search |
| Speed (Valkey cache) | Rate limits on heavy usage |
| Tech guides and tutorials | Source diversity |

### Web Scraping: Crawl4AI (fallback)

Use Crawl4AI when SearXNG fails or for advanced web tasks. See the `crawl4ai` skill.

| Tool | When to use |
|------|-------------|
| `md` | SearXNG returned empty/blocked content, or page requires JavaScript |
| `screenshot` | User wants a screenshot of a page |
| `pdf` | User wants a PDF capture of a page |
| `html` | Raw HTML is needed |
| `crawl` | Full crawl with browser/crawler tuning (wait selectors, timeouts, stealth) |
| `execute_js` | Disabled by default — `crawler_config.js_code` is blocklisted too; use `md` `f: "raw"` + parse |

### Web workflow

1. **Search** → `searxng_web_search`
2. **Read a URL** → `web_url_read`
3. **SearXNG 429, or results lack official docs/GitHub** → `websearch`
4. **URL empty/blocked/JS-required** → Crawl4AI `md`
5. **Screenshots/PDFs** → Crawl4AI `screenshot` or `pdf`
6. **Dynamic content** → Crawl4AI `crawl` with `crawler_config.wait_for`
7. **Always** summarize in your own words — no raw dumps, no verbatim excerpts.

### Architecture Documentation: arc42

arc42 skills are available for documenting software architecture:

- **Sections 1-12** — Interactive guided documentation for each arc42 section
- **arc42-review** — Review sections for completeness and consistency
- **arc42-lint** — Validate cross-section ID consistency

Use when the user wants to create or review architecture documentation following the arc42 template.

### GitLab: glab CLI

When a task touches GitLab (MRs, issues, CI/CD, releases, packages, API), use
the `glab` CLI — see the `glab` skill first and prefer it over raw API calls.
`glab-stack` covers stacked merge requests; `gitlab-selfhost` covers
self-hosted instance and runner patterns.

### Code Indexing: Qdrant

Semantic search over codebases using vector embeddings and tree-sitter parsing. See the `qdrant` skill.

**IMPORTANT:** Always use the venv Python for Qdrant tools — never the system Python:
```bash
~/.agents/tools/qdrant/.venv/bin/python ~/.agents/tools/qdrant/bin/index-codebase.py ...
```

| Tool | When to use |
|------|-------------|
| `qdrant-find` | Open-ended code search by functionality — try first, then `grep` |
| `/index` | Index/re-index the codebase or install git hooks |
