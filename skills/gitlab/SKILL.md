---
name: gitlab
description: >
  GitLab and GitLab Runner patterns for self-managed instances — omnibus in
  Docker, token/API authentication, OIDC sign-in against Keycloak, runner
  registration, and the integration traps. Use when deploying or debugging
  GitLab, glab, CI runners, or SSO login flows. Trigger on phrases like
  "gitlab", "runner", "omniauth", "401 Unauthorized", "personal access
  token", "unable to exchange code".
license: MIT
compatibility: opencode
metadata:
  type: integration
  domain: devops
---

# GitLab

Rules that exist because violating them cost a debugging cycle, gathered from
a self-managed GitLab CE in Docker with Keycloak SSO and a docker-executor
runner.

---

## Tokens and API authentication

- GitLab 19 accepts `PRIVATE-TOKEN:` and `Authorization: Bearer <pat>` — but
  **rejects the legacy `Authorization: Basic base64("oauth2:<pat>")`** with
  401. A tool failing with 401 while `curl` with the same token succeeds is
  sending the wrong scheme.
- `glab` must store its own auth (`glab auth login --stdin`); a hand-written
  `config.yml` makes it fall back to the rejected scheme. See the `ansible`
  skill for the task pattern.
- Mint short-lived admin PATs through
  `docker exec gitlab gitlab-rails runner "…personal_access_tokens.create!…"`
  for scripted setup, and destroy them at the end. The create API returns the
  plaintext **once**; the database keeps only a digest.
- `curl -u user:password` does not work against the API on modern instances —
  use a PAT or OIDC.

## Omnibus configuration in Docker

- `GITLAB_OMNIBUS_CONFIG` is evaluated on every container start and is **not**
  written to `gitlab.rb` — drive it from configuration data so the source of
  truth stays in git. Same for the pinned image tag.
- The three volumes (`/etc/gitlab`, `/var/log/gitlab`, `/var/opt/gitlab`) are
  the whole state; a data disk that holds them is the backup story.
- For memory-constrained boxes follow
  `docs.gitlab.com/omnibus/settings/memory_constrained_envs`: CE, `puma
  ['worker_processes'] = 0`, `sidekiq['concurrency'] = 10`, the monitoring
  stack off, jemalloc decay tuning, and real swap.

## OIDC sign-in (Keycloak or any IdP)

- OmniAuth 2 answers the request phase on **POST only** — `curl -I
  /users/auth/<provider>` returning 404 is normal, not a broken integration.
- Verify the round trip in three layers before touching the browser: the
  discovery document fetchable **from inside the app's container**, the
  redirect carrying `client_id`, and finally one real login click.
- The app must trust the IdP's CA. For omnibus that is
  `/etc/gitlab/trusted-certs/`; for Nextcloud AIO the supported knob is
  `NEXTCLOUD_TRUSTED_CACERTS_DIR` on the mastercontainer (a host directory
  mounted read-only — survives recreation, unlike copies into containers).
- Users are auto-created and auto-linked by **email** — keep the IdP email and
  the app account email identical.

## Runner

- Registration uses the `glrt-…` authentication token created in the UI;
  register query-then-add on `config.toml`, with `no_log` — the token passes
  through the command line.
- The docker executor shares the host daemon: job images land wherever
  `data-root` points, and job isolation is only as good as that daemon's.
- The runner container trusts the instance CA from
  `/etc/gitlab-runner/certs/<hostname>.crt` — one file per hostname.

## Keycloak admin API quirks

- Field names are camelCase and the UI labels do not always match: "Home URL"
  is `baseUrl` — unknown fields are silently dropped or rejected with
  `Unrecognized field` (400).
- A confidential client with PKCE wants
  `attributes: pkce.code.challenge.method: S256`; its `secret` can be set in
  the create body, so the credential never has to leave your vault.
