---
description: Index the current codebase into Qdrant for semantic search
agent: build
---

1. Check if Qdrant is running:
   ```bash
   curl -sf http://localhost:6333/healthz || docker compose -f ~/.agents/tools/qdrant/docker-compose.yml up -d
   ```

2. Check if git hooks are installed. Look for `core.hooksPath`:
   ```bash
   HOOKS_PATH=$(git config core.hooksPath 2>/dev/null || echo ".git/hooks")
   ```
   If `core.hooksPath` is set to something other than `.git/hooks`, warn the user that hooks in `.git/hooks/` won't fire and offer to install into `$HOOKS_PATH` instead.

3. Install git hooks (skip if already present and not forcing):
   ```bash
   HOOKS_DIR="$(git rev-parse --show-toplevel)/${HOOKS_PATH}"
   cp ~/.agents/tools/qdrant/git-template/hooks/post-commit "$HOOKS_DIR/post-commit"
   cp ~/.agents/tools/qdrant/git-template/hooks/post-checkout "$HOOKS_DIR/post-checkout"
   chmod +x "$HOOKS_DIR/post-commit" "$HOOKS_DIR/post-checkout"
   ```

4. Create marker file (enables git hooks for this repo):
   ```bash
   touch "$(git rev-parse --show-toplevel)/.qdrant-index"
   ```

5. Write per-project opencode MCP config. Read existing `.opencode/opencode.json` first and merge (don't overwrite other tool configs):
   ```bash
   ~/.agents/tools/qdrant/.venv/bin/python ~/.agents/tools/qdrant/bin/index-codebase.py --write-config "$(git rev-parse --show-toplevel)"
   ```

6. Run the indexer:
   ```bash
   ~/.agents/tools/qdrant/.venv/bin/python ~/.agents/tools/qdrant/bin/index-codebase.py "$(git rev-parse --show-toplevel)" $ARGUMENTS
   ```
   If user passed `--reindex`, add that flag. Otherwise do incremental.

7. Report results: files scanned, chunks indexed, files skipped, collection name.
