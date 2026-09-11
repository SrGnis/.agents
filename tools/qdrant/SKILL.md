---
name: qdrant
description: >
  Semantic code search over indexed codebases using Qdrant vector database.
  Use when the user wants to find code by functionality rather than keywords,
  search for implementations across a codebase, or ask natural language
  questions about code. Trigger on phrases like "find where", "how is X
  implemented", "search for code that", "semantic search".
license: MIT
compatibility: opencode
metadata:
  type: code-search
  protocol: mcp
---

# Qdrant Semantic Code Search

Use this skill to search codebases using natural language queries via the
Qdrant vector database. The indexer uses tree-sitter for AST-aware code
parsing and stores code chunks with semantic embeddings.

---

## Available Tools

| Tool | Purpose |
|------|---------|
| `qdrant-find` | Search for code by natural language description |
| `qdrant-store` | Store information manually (read-only mode is default) |

---

## qdrant-find

Search for relevant code snippets using natural language.

```json
{ "query": "how is authentication implemented" }
```

The query should describe **what** the code does, not how it's written.

### Good queries

- "how is user authentication implemented"
- "database connection pooling"
- "error handling for API requests"
- "caching layer for expensive computations"
- "configuration loading from environment variables"

### Bad queries

- "def authenticate" (keyword search, use grep instead)
- "class User" (too specific, use grep)
- "import json" (not semantic)

---

## When to Use

- Finding implementations by functionality
- Understanding how a feature is spread across files
- Locating code patterns across the codebase
- Exploring unfamiliar codebases

## When NOT to Use

- Finding exact strings or symbols (use `grep`)
- Finding files by name (use `glob`)
- Reading specific known files (use `read`)

---

## Workflow

1. Formulate a natural language query describing what you're looking for
2. Call `qdrant-find` with the query
3. Review results — each includes file path, line numbers, and code snippet
4. Use `read` to examine the full context if needed

---

## Tips

- The index is per-branch — search results reflect the current branch's code
- Uncommitted code may not be indexed yet (indexing happens on commit)
- Run `/index` to manually index the codebase if needed
- Queries work best when describing functionality, not syntax
- Results include file path and line numbers for direct navigation
- Indexes code (Python, JS/TS, Rust, Go, Java, C/C++, Ruby, PHP, Kotlin, Swift, C#, Scala, Lua, Haskell), docs (Markdown), scripts (Bash), and configs (YAML, TOML)

---

## Error Handling

| Symptom | Fix |
|---------|-----|
| No results | Codebase may not be indexed — run `/index` |
| Stale results | Re-index with `/index --reindex` |
| Connection refused | Check if Qdrant is running (`docker ps`) |
| Collection not found | Run `/index` to create the collection |
