---
description: Install the optional arc42 documentation skills into this project
agent: build
---

Install the optional arc42 skill bundle into the current project.

1. Run the bundle installer. It resolves the git root itself (falling back to the current directory) and defaults to copying:
   ```bash
   bash ~/.agents/bundles/arc42/install.sh $ARGUMENTS
   ```
   Supported flags: `--link`, `--force`, `--remove`, `--dry-run`.

2. If the script reports skipped skills, they already exist. Mention that `--force` replaces them and `--link` makes them track `~/.agents`.

3. Report the installed skill IDs (`arc42-section-01` through `arc42-section-12`, `arc42-review`, `arc42-lint`) and tell the user to run `/reload` if the skills do not appear immediately.

Do not copy files by hand and do not modify `.opencode/opencode.json`.
