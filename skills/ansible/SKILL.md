---
name: ansible
description: >
  Ansible patterns and hard-won conventions for infrastructure automation.
  Use when writing or debugging Ansible playbooks, roles, inventories or
  group_vars — especially idempotency problems, CLI-tool state management,
  secrets handling, cross-host tasks, or YAML/Jinja pitfalls. Trigger on
  phrases like "write a playbook", "why is this not idempotent", "changed on
  every run", "ansible-lint", "role variables".
license: MIT
compatibility: opencode
metadata:
  type: automation
  domain: infrastructure
---

# Ansible

Patterns that have actually been needed. Each rule below exists because
violating it cost a debugging cycle.

---

## The single most important rule

**Facts live in `group_vars`, code lives in `roles`.** A playbook must not
contain a fact about the environment. Hostnames, addresses, users, DNS
records, image tags — all data. Adding a host should be one stanza in the
inventory; adding a user, three lines of YAML.

## Idempotency is not optional

Every playbook must report `changed=0` on a second run. When touching a
`command:` task, ask: does it report `changed` when nothing changed?

**Query-then-add** is the pattern for CLI tools without an idempotent mode:

```yaml
- ansible.builtin.command: firewall-cmd --permanent --query-service=https
  register: q
  changed_when: false
  failed_when: false
- ansible.builtin.command: firewall-cmd --permanent --add-service=https
  when: q.rc != 0
  changed_when: true
```

Do **not** infer change from stdout text (`changed_when: "'success' in stdout"`).
`firewall-cmd`, `ipa`, `setsebool` and friends all report state in ways that
defeat it.

## Handlers are a trap

Handlers do **not** run when a play fails. That leaves systems half-configured
after a failed deploy — e.g. systemd units never generated. Prefer an
unconditional command with `changed_when: false` when the operation is
idempotent in effect (`update-ca-trust`, `sysctl -p`, `firewall-cmd --reload`,
`daemon_reload`).

If `ansible-lint` flags `no-handler` on a task gated by `is changed`, resolve
it the same way rather than converting to a handler.

## Become is misleading

A group var `ansible_become: true` **beats** the task keyword `become: false`:
the task silently runs as root and writes root-owned files into user homes.
For user-context work use `become: true` + `become_user:` — besides being
explicit, sudo re-initializes the target's groups, so a membership added
moments earlier (e.g. `docker`) applies in the same play.

## Modules that are not what they look like

- `copy`/`template` do **not** create missing parent directories — create them
  explicitly or the task fails on a fresh box.
- `known_hosts` + `ssh-keyscan`: the scan prints trailing `# banner` comment
  lines that the module happily appends **every run**. Filter to the key line
  (`select('search', 'ssh-ed25519') | first`); non-standard ports need
  `name: "[host]:port"` and a key line the module can rewrite to match.
  `lookup('pipe', ...)` runs on the controller, not the target.
- A unit with an unmet `Condition*` (e.g. chrony's `ConditionCapability` in an
  LXC guest) is *skipped*, so `state: started` reports `changed` forever.
  Gate the task with a data flag instead of fighting the condition.
- Not every `ansible.builtin.*` you remember is core: `filesystem` and `mount`
  live in community collections. In a dependency-free repo fall back to
  `blkid`/`mkfs` query-then-add, `lineinfile` for fstab, and an unconditional
  `mount -a`.

## Secrets

- `no_log: true` on anything carrying a password or bearer token. `uri` and
  `command` dump `invocation` on failure, which would print the credential.
- One vault per group: `group_vars/<group>/vault.yml`.
- **One variable, one file.** A variable defined in both `main.yml` and
  `vault.yml` of the same group silently resolves to the `vault.yml` value —
  files in a `group_vars/<group>/` directory merge alphabetically. This has
  cost hours of debugging.
- `ansible-vault view` and `ansible-inventory --host` **decrypt** values. Never
  print their output.
- Keep `vault.yml` **whole-file** encrypted (`ansible-vault encrypt`).
  `encrypt_string` emits inline `!vault` YAML that `ansible-vault view` then
  refuses to read. To edit a vault without exposing it: `view > tmp` (a file,
  not output), change it, `encrypt --output vault.yml tmp`, `shred tmp`.
  Diagnose secret problems by length and character class only, never by value.

## Cross-host tasks

When a role on host A needs credentials that live on host B, read them from B
rather than widening the vault scope:

```yaml
delegate_to: "{{ groups['ipaservers'][0] }}"
```

Every command that uses those credentials must `delegate_to` as well — and so
must any `slurp` of its output, otherwise the read happens on the wrong host.

## YAML and Jinja pitfalls

- **`: ` inside an unquoted scalar parses as a mapping.** Quote anything with a
  colon followed by a space — command output patterns, sed expressions,
  `key: value` literals inside strings.
- Jinja has **no list comprehensions**. Hardcode fixtures in test playbooks.
- Task-scoped `vars:` do not survive into the next task — use `set_fact`.
- A multi-line `state: >-` makes ansible-lint write module args to a filename
  and crash. Hoist the expression into `set_fact`.
- Free-form `command:` word-splits on spaces. Use `argv:` whenever an argument
  contains a space, or the value silently becomes several arguments.
- Module args like `chdir`, `stdin`, `creates` belong under the module key or
  `args:` — at task level ansible-lint reports "conflicting action statements".
- `select('match', pat)` anchors at the **start** of the string (it is
  `re.match`); use `select('search', pat)` for a substring.

## CLI tool state

Tools that manage their own credentials must write them themselves. A
hand-written config file can authenticate differently than the tool's own
login flow — glab in a hand-rolled `config.yml` sent `Basic oauth2:<token>`,
which GitLab 19 rejects, while `glab auth login --stdin` stores the token in
the shape the tool serves correctly. Feed the token with `stdin:` under
`args:`, guard with query-then-add on `auth status`, and run the tool with
`chdir` set to a directory the user can read.

For third-party releases pinned as data, probe the installed version
(`when: pinned_version not in probe.stdout`) rather than reinstalling every
run — `apt` happily leaves an upstream `.deb` newer than the distro candidate
in place.

## Style

- Fully qualified module names (`ansible.builtin.copy`).
- Role variables prefixed with the role name.
- `copy` with inline `content:` rather than a template for short files.
- Distro awareness via `ansible_facts.pkg_mgr` / `os_family`, not `when` chains
  on distribution names. Package index refresh is distro-specific and must come
  **before** any install — a host cannot install packages until it resolves
  names, so DNS configuration must precede package installation.

## Verify before claiming done

1. `ansible-lint` clean
2. the playbook runs twice — second run `changed=0`
3. an **observable** check, not just "the task reported ok" — a real DNS query,
   a certificate read back, a service responding, an authentication attempt

Beware pipeline masks in those checks: `cmd | tail; echo $?` reports `tail`'s
status, so a failing step upstream looks green. Capture the command's own rc.

If something half works, say so explicitly rather than reporting success.
