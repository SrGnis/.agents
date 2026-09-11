# Qdrant Tool

Semantic code search over indexed codebases using [Qdrant](https://qdrant.tech/) vector database with tree-sitter AST parsing.

## What It Does

- Indexes codebases into Qdrant using tree-sitter for semantic code chunking
- Enables natural language code search ("how is authentication implemented")
- Auto-indexes on `git commit` and `git switch` via git hooks
- Content-addressable deduplication using git blob hashes
- Branch-aware indexing — same file on different branches shares points

## Architecture

```
git commit / git switch
        │
        ▼
 ┌──────────────┐
 │  Git Hooks   │  post-commit: index changed files
 │              │  post-checkout: index on branch switch
 └──────┬───────┘
        │ nohup, background
        ▼
 ┌──────────────┐     ┌──────────────┐
 │ index-codebase│────▶│  tree-sitter │  parse code into chunks
 │ .py           │     └──────────────┘
 └──────┬───────┘
        │
        ▼
 ┌──────────────┐     ┌──────────────┐
 │  Qdrant DB   │◀────│  qdrant-     │  batch upsert with embeddings
 │  (Docker)    │     │  client      │
 └──────────────┘     └──────────────┘

 ┌──────────────┐
 │  /index cmd  │  full re-index + hook install
 └──────────────┘
```

## Setup

```bash
# From the agents root
./setup.sh
```

This will:
1. Install `uv` if missing (Python package manager)
2. Create a Python venv with tree-sitter, qdrant-client, fastembed
3. Start Qdrant container via Docker Compose
4. Register a disabled global MCP stub in opencode config
5. Symlink the skill to `skills/qdrant/`

Then in any repo:
```bash
# Install hooks + initial index + per-project MCP config
/index
```

## Manual Usage

```bash
# Start the container
docker compose up -d

# Test the API
curl http://localhost:6333/healthz

# Run indexer manually
python ~/.agents/tools/qdrant/bin/index-codebase.py /path/to/repo

# Force full re-index
python ~/.agents/tools/qdrant/bin/index-codebase.py /path/to/repo --reindex

# Stop the container
docker compose down
```

## How Indexing Works

### Triggers

| Trigger | Hook | When | What gets indexed |
|---------|------|------|-------------------|
| `git commit` | `post-commit` | After every commit | Files changed in that commit |
| `git switch` / `git checkout` | `post-checkout` | After branch switch | Full branch scan (incremental) |
| `/index` command | Manual | User runs it | Full re-index + hook setup |

### Deduplication

Point IDs are content-addressable: `hash(file_path + git_blob_hash + line_from + symbol_name)`

- Same content on same branch → same ID → upsert = no duplicate
- Same file on different branch → same content = shared point, branch added to payload
- File changed → blob hash changes → new IDs for all chunks in that file

### Branch Handling

Points store `branches: ["main", "feature/x"]` as a payload list. When a file is deleted on one branch, the branch is removed from the payload. Points are only deleted when no branches reference them.

### Renames and Deletes

- **Rename**: `git diff-tree -M` detects renames; file_path payload is updated
- **Delete**: Points have the branch removed from their `branches` list

### Concurrency

State file access is serialized via `flock`. Git hooks acquire a non-blocking lock — if another indexer is running, the hook silently skips. `/index` acquires a blocking lock.

## Supported Languages

**Code:** Python, JavaScript, TypeScript, JSX, TSX, Rust, Go, Java, C, C++, Ruby, PHP, Kotlin, Swift, C#, Scala, Lua, Haskell

**Scripts:** Bash (.sh, .bash)

**Docs:** Markdown (.md)

**Config:** YAML (.yaml, .yml), TOML (.toml)

## Configuration

Edit `.env` to change settings:

```bash
# Qdrant version
QDRANT_VERSION=latest

# Ports
QDRANT_PORT=6333
QDRANT_GRPC_PORT=6334
```

## Git Hooks

Hooks are installed per-repo by `/index`. They check for a `.qdrant-index` marker file before running. This marker should be committed to the repo so all team members share the indexing decision.

```bash
# Recommended: commit the marker
echo ".qdrant-index" >> .gitignore  # NO — commit it instead
git add .qdrant-index
git commit -m "Enable Qdrant indexing"

# Or make it local-only
echo ".qdrant-index" >> .git/info/exclude
```

### Global Template (optional)

To auto-install hooks in all new repos:

```bash
git config --global init.templateDir ~/.agents/tools/qdrant/git-template/
```

The global hook checks for `.qdrant-index` before indexing — repos without the marker are silently skipped.

### core.hooksPath

If a repo uses `core.hooksPath` (Husky, pre-commit), `/index` will detect this and warn. Install the hooks into the configured hooks path manually.

## Dependencies

- Docker
- uv (auto-installed)
- Python 3.12 (auto-installed by uv, required by tree-sitter-languages)
- Python packages (installed into `.venv` by `install.sh`):
  - tree-sitter
  - tree-sitter-languages
  - qdrant-client[fastembed]
