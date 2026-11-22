# arc42 bundle

Optional arc42 architecture-documentation skills. Not installed globally: the bundle lives outside `skills/`, so OpenCode does not advertise it until it is installed into a project.

## Install

From the project you want to document:

```bash
~/.agents/bundles/arc42/install.sh
```

Or in OpenCode: `/init_arc42`.

The installer resolves the git root (falling back to the current directory) and copies these skills into `<root>/.opencode/skills/`:

| Skill | Purpose |
|-------|---------|
| `arc42-section-01` … `arc42-section-12` | Interactive documentation of each arc42 section |
| `arc42-review` | Review sections for completeness and consistency |
| `arc42-lint` | Cross-section ID consistency validation |

## Options

| Flag | Effect |
|------|--------|
| `--link` | Symlink instead of copy, tracking `~/.agents` updates |
| `--force` | Replace skills that already exist |
| `--remove` | Remove the bundle from the project |
| `--dry-run` | Show what would happen |

Existing skills are skipped unless `--force` is given, so re-running is safe. Run `/reload` in OpenCode if the skills do not appear immediately.

## Notes

- Copies are self-contained and safe to commit; teammates do not need `~/.agents`.
- Symlinks are relative, so they survive moving the project but break if `~/.agents` is removed.
