# .agents

A modular configuration framework for enhancing AI coding agents with skills, tools, and external integrations. Designed for [OpenCode](https://github.com/anomalyco/opencode) but extensible to other harnesses.

## Overview

This repository provides:

- **Agents** — Custom agent personas with scoped capabilities
- **Skills** — Instruction sets that teach agents how to perform specific tasks
- **Tools** — Self-hosted services (Docker) with MCP server integrations
- **Setup automation** — One-command install/uninstall with harness auto-detection

## Directory Structure

```
.agents/
├── agents/              # Agent definitions (YAML frontmatter + markdown)
│   └── ask.md           # Read-only code analyst and research assistant
├── commands/            # Custom slash commands
│   └── index.md         # /index — index codebase into Qdrant
├── skills/              # Skill definitions loaded by agents at runtime
│   ├── arc42/           # 14 skills for arc42 architecture documentation
│   ├── crawl4ai/        # Web scraping via Crawl4AI (symlink from tool)
│   ├── qdrant/          # Semantic code search via Qdrant (symlink from tool)
│   └── searxng/         # Web search via SearXNG (symlink from tool)
├── tools/               # Self-hosted tool installations
│   ├── crawl4ai/        # Crawl4AI Docker + MCP server + harness adapters
│   ├── qdrant/          # Qdrant Docker + indexer + git hooks
│   └── searxng/         # SearXNG Docker + MCP server + harness adapters
├── config.env           # Enable/disable tools (SEARXNG_ENABLED, CRAWL4AI_ENABLED, QDRANT_ENABLED)
├── setup.sh             # Main setup script — reads config.env, runs installers
└── AGENTS.md            # Global agent rules (symlinked to opencode config)
```

## Quick Start

```bash
# 1. Edit config.env to enable/disable tools
cat config.env
# SEARXNG_ENABLED=true
# CRAWL4AI_ENABLED=true

# 2. Run setup
./setup.sh

# 3. Restart your coding agent (e.g., opencode) to load new MCP servers
```

`setup.sh` always symlinks `AGENTS.md` to `~/.config/opencode/AGENTS.md` so global agent rules are loaded by all OpenCode projects.

### Environment

| Variable | Default | Used by |
|---|---|---|
| `AGENTS_HOME` | `~/.agents` | Qdrant indexer state dir and git hooks — override if you keep this repo at a non-default path |
| `XDG_CONFIG_HOME` | `~/.config` | OpenCode config location (used by harness adapters) |

### Prerequisites

- Docker
- pnpm (for global npm MCP server packages)
- uv (auto-installed by Qdrant tool for Python indexing)

## Tools

### SearXNG

Self-hosted meta search engine with MCP integration. Provides private web search, URL reading, and autocomplete suggestions.

| Component | Details |
|-----------|---------|
| Container | `searxng/searxng` + `valkey/valkey` (Redis-compatible cache) |
| MCP Server | `mcp-searxng` (npm) |
| Default Port | `8888` |
| Config | `tools/searxng/.env` |

**Capabilities:** `searxng_web_search`, `searxng_search_suggestions`, `searxng_instance_info`, `web_url_read`

### Crawl4AI

Browser-based web scraping with JavaScript rendering, anti-bot bypass, screenshots, and PDF generation.

| Component | Details |
|-----------|---------|
| Container | `unclecode/crawl4ai` |
| MCP Server | `crawl4ai-mcp-sse-stdio` (npm) |
| Default Port | `11235` |
| Config | `tools/crawl4ai/.env` |

**Capabilities:** `crawl`, `md`, `html`, `screenshot`, `pdf`, `execute_js`

### Qdrant

Semantic code search using vector embeddings. Indexes codebases with tree-sitter AST parsing, stores in Qdrant vector database, and enables natural language code search via MCP.

| Component | Details |
|-----------|---------|
| Container | `qdrant/qdrant` |
| MCP Server | `mcp-server-qdrant` (uvx, per-project config) |
| Default Port | `6333` (REST), `6334` (gRPC) |
| Config | `tools/qdrant/.env` |
| Indexer | `tools/qdrant/bin/index-codebase.py` (Python, tree-sitter) |
| Git Hooks | `post-commit`, `post-checkout` (auto-index on commit/switch) |

**Capabilities:** `qdrant-find` (semantic code search), `/index` command (indexing + hook setup)

**How it works:**
- `/index` installs git hooks and does initial index
- `post-commit` hook indexes changed files after each commit
- `post-checkout` hook indexes on branch switch
- Git blob hashes provide content-addressable deduplication
- Branch-aware: same file on different branches stored as shared points with branch payload filter
- Per-project collection names (derived from git remote URL)
- Per-project MCP config written by `/index` to `.opencode/opencode.json`

```
tools/qdrant/
├── docker-compose.yml
├── .env / .env.example
├── install.sh
├── uninstall.sh
├── SKILL.md
├── README.md
├── .venv/                 # Python venv (tree-sitter, qdrant-client, fastembed)
├── bin/
│   └── index-codebase.py  # Main indexer
├── git-template/
│   └── hooks/
│       ├── post-commit
│       └── post-checkout
└── opencode/
    ├── detect.sh
    ├── install.sh         # Writes disabled global stub
    └── uninstall.sh
```

## Tools Architecture

Each tool follows the same pattern:

```
tools/<name>/
├── docker-compose.yml   # Container definition
├── .env                 # Runtime config (ports, versions, tokens)
├── .env.example         # Template with documentation
├── install.sh           # Main installer (Docker + npm + harness config)
├── uninstall.sh         # Cleanup script
├── SKILL.md             # Skill documentation (symlinked to skills/)
├── README.md            # Tool-specific documentation
└── opencode/            # Harness adapter
    ├── detect.sh        # Checks if this harness is installed
    ├── install.sh       # Writes MCP config to harness
    └── uninstall.sh     # Removes MCP config from harness
```

### Harness Adapters

Tools auto-detect installed coding agent harnesses and prompt for selection. Currently supported:

- **OpenCode** — Writes to `~/.config/opencode/opencode.jsonc`

To add a new harness, create a directory under `tools/<name>/` with `detect.sh`, `install.sh`, and `uninstall.sh`.

## Skills

Skills are markdown files with YAML frontmatter that instruct agents how to use specific capabilities. They are loaded at runtime and provide:

- Tool descriptions and usage patterns
- Parameter documentation with examples
- Recommended workflows
- Error handling guidance

### Available Skills

| Skill | Description |
|-------|-------------|
| `searxng` | Web search, URL reading, autocomplete suggestions |
| `crawl4ai` | JS-rendered scraping, screenshots, PDFs, JS execution |
| `qdrant` | Semantic code search via vector embeddings |
| `arc42-section-01` through `arc42-section-12` | Interactive arc42 architecture documentation |
| `arc42-review` | Review arc42 sections for completeness and consistency |
| `arc42-lint` | Cross-section ID consistency validation |

### Skill Sources

- **Tool skills** — Defined in `tools/<name>/SKILL.md`, symlinked to `skills/<name>/` during installation
- **Standalone skills** — Defined directly in `skills/` (e.g., arc42)

## Agents

Custom agent personas defined as markdown with YAML frontmatter. Each agent specifies:

- Description and mode (primary, subagent)
- Temperature setting
- Tool permissions (read/write/execute per tool)
- System prompt with workflows and guidelines

### `ask` Agent

A read-only research assistant that can:
- Explore codebases (read, glob, grep)
- Fetch web content
- Brainstorm ideas
- Cannot modify files or execute commands

## AGENTS.md

Global rules loaded by all agents across all projects. Symlinked to `~/.config/opencode/AGENTS.md` during setup.

Contains:
- **Code style** — Concise output, no comments unless asked, follow conventions
- **Security** — Never expose secrets or commit keys
- **Verification** — Run lint/typecheck after changes
- **Git** — Stage only intended files, match repo commit style
- **Tool usage** — When and how to use SearXNG, Crawl4AI, Qdrant, and arc42 skills
- **Workflow** — SearXNG-first approach with Crawl4AI fallback, Qdrant for code search

## Configuration

### config.env

```bash
# Set to "true" to enable, "false" to disable
SEARXNG_ENABLED=true
CRAWL4AI_ENABLED=true
QDRANT_ENABLED=true
```

### Tool-specific .env Files

Each tool has its own `.env` for ports, versions, and authentication:

```bash
# tools/searxng/.env
SEARXNG_VERSION=latest
SEARXNG_HOST=[::]
SEARXNG_PORT=8888

# tools/crawl4ai/.env
CRAWL4AI_VERSION=latest
CRAWL4AI_PORT=11235
CRAWL4AI_API_TOKEN=  # Generate with: openssl rand -hex 32
```

## Adding a New Tool

1. Create `tools/<name>/` with:
   - `docker-compose.yml`
   - `.env` and `.env.example`
   - `install.sh` and `uninstall.sh`
   - `SKILL.md`
   - `opencode/detect.sh`, `opencode/install.sh`, `opencode/uninstall.sh`

2. Add `<NAME>_ENABLED=true` to `config.env`

3. Add a `process_tool` call in `setup.sh`

## Adding a New Skill

1. Create `skills/<name>/SKILL.md` with YAML frontmatter:

```yaml
---
name: my-skill
description: >
  What this skill does and when to use it.
license: MIT
compatibility: opencode
metadata:
  type: category
  protocol: mcp
---
```

2. Add tool usage, parameters, examples, and error handling

## License

MIT
