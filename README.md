# devbox

A sandboxed devcontainer template for running AI coding agents (Claude
Code, etc.) against real project files without giving them full host
access.

## What it does

- Scopes the container to one project directory only (bind mount).
- Drops all Linux capabilities except a minimal explicit set.
- Firewalls all outbound traffic to an explicit domain allowlist,
  fail-closed, self-verified on every start.
- Blackholes cloud metadata endpoints (SSRF/credential-theft mitigation).
- Injects real API credentials via a local HTTPS proxy so the agent
  process never holds the raw key.
- Isolates each tool's own config/session home in a per-project named
  Docker volume, not a bind mount.

## Security notes

This sandbox reduces the agent's blast radius; it doesn't eliminate
it. Worth knowing before you rely on it:

- **Allowlisted hosts can still be abused.** The firewall
  (`features/firewall/network-policy.json`) blocks arbitrary
  destinations, not arbitrary *uses* of permitted ones. GitHub, the
  npm/PyPI/crates registries, and the Anthropic/OpenAI APIs are all
  allowlisted and all accept user-supplied content — a compromised or
  adversarial agent could still leak data via a public commit/gist, a
  published package, or a crafted API request. Trim the allowlist to
  what a given project actually needs.
- **Injected credentials carry their full granted scope.** The
  credential proxy (`features/credentials`) keeps the raw key out of
  the agent process, but a request using an injected credential
  succeeds with whatever permissions that credential has. Use scoped,
  least-privilege tokens, not broad personal ones. Injection events
  (header + host, never the value) are logged inside the container to
  `/var/log/devbox/credential-injections.log`.
- **Agent memory — and login — persists per project, not globally.**
  Tools that keep their own long-term memory/notes and credentials
  (e.g. Claude Code, which stores its OAuth token in
  `~/.claude/.credentials.json`) get `/home/node/.claude` mounted as a
  named Docker volume keyed to the project folder's basename. That
  volume is isolated between projects but not wiped between sessions
  on the same one. Two consequences: content an agent is tricked into
  writing there (via a prompt injection from an untrusted page, file,
  or tool result) would be reloaded as trusted context in a later
  session — worth auditing occasionally if this matters to you — and
  you'll need to `claude login` again the first time you `devbox` into
  each *new* project folder, even if you've already logged in from
  another one, because each folder gets its own empty volume. Re-running
  `devbox` on a folder you've already logged in from reuses that
  folder's volume, so the session carries over there.

## Codex CLI

OpenAI's [Codex CLI](https://github.com/openai/codex) works inside devbox.
A couple of things to know:

- **The `codex_apps` MCP server needs `chatgpt.com` allowlisted.** Codex's
  built-in `codex_apps` MCP server (ChatGPT connectors/apps) calls out to
  `chatgpt.com/backend-api/`; without it on the firewall allowlist the
  connection hangs until Codex's own 30s MCP startup timeout gives up,
  printing `MCP client for codex_apps timed out after 30 seconds`. This
  is allowlisted by default (`features/firewall/network-policy.json`,
  `openai` group). If you still see the timeout — e.g. because your
  project's bootstrapped `.devcontainer/` predates this — add
  `chatgpt.com` to your allowlist (see below) or upgrade your project's
  `.devcontainer/` to a newer template version.
- **The bubblewrap warning on startup is expected.** Codex normally
  sandboxes the commands *it* runs using Linux user namespaces
  (bubblewrap). Building those namespaces needs capabilities devbox's
  container deliberately drops, so Codex can't do it and prints a
  startup warning and falls back to its bundled bubblewrap helper. In
  practice this means Codex's own per-command sandboxing is weaker than
  it would be on a bare host — you're relying on devbox's outer
  container sandbox (dropped capabilities, firewall) instead. This has
  been fine in testing, but if you notice odd behavior around Codex's
  file edits or command execution, that's the known limitation to
  suspect first.

**Adding domains for tools devbox doesn't know about yet:** rather than
editing the vendored `network-policy.json`, add one domain per line to
`.devbox/allowed-domains` in your project root (created if missing,
`#` comments allowed) and restart the container (or re-run
`sudo /usr/local/bin/init-firewall.sh` inside it) to pick it up.

## Requirements

- Docker
  - macOS: Docker Desktop or [OrbStack](https://orbstack.dev/)
  - Linux: Docker Engine, plus your user in the `docker` group:
    ```bash
    sudo usermod -aG docker $USER
    newgrp docker          # or log out/in
    docker ps               # confirm no "permission denied" error
    ```
- `curl` — not installed by default on some minimal Ubuntu setups:
  ```bash
  sudo apt install curl -y
  ```
- The [devcontainer CLI](https://github.com/devcontainers/cli):
  ```bash
  curl -fsSL https://raw.githubusercontent.com/devcontainers/cli/main/scripts/install.sh | sh
  echo 'export PATH="$HOME/.devcontainers/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
  ```
  This bundles its own Node.js runtime, so it works regardless of your
  system Node version.

  Alternative, only if you already have a Node.js version new enough to
  satisfy the CLI's `engines` requirement (apt's default Node 18.19.1 on
  Ubuntu is not):
  ```bash
  npm install -g @devcontainers/cli
  ```

## Install

```bash
git clone <YOUR_REPO_URL> ~/.devbox-template
echo 'source ~/.devbox-template/devbox.sh' >> ~/.bashrc   # or ~/.zshrc
source ~/.bashrc
```

## Use

```bash
devbox <project-dir>
devbox doctor          # check requirements and diagnose setup issues
```

First run on a directory with no `.devcontainer/` bootstraps one from
this template. Each project's copy is then independent — edits here
don't propagate to already-bootstrapped projects.

`devbox <project-dir>` also runs these checks automatically before
building, and stops with the same fix commands if anything's missing.

Bootstrapping only copies the template's files, not its `.git` — a
project's `.devcontainer/` is never a clone of this repo, so git
commands run inside a bootstrapped project can't accidentally target
this template's remote.

## Platform notes

Tested on macOS (Docker Desktop, OrbStack) and Linux (Docker Engine,
Ubuntu 24.04) — build, firewall, and credential proxy all work on
both. On Linux, make sure your user is in the `docker` group (see
Requirements); Docker Engine enforces this where Docker
Desktop/OrbStack don't.

## Troubleshooting

Run `devbox doctor` first — it checks for these exact issues and
prints the fix command for whichever one applies.

**`npm install -g @devcontainers/cli` fails with `EBADENGINE`**
Your system Node is older than the CLI requires (e.g. Node 18.19.1
from apt on Ubuntu). Use the standalone install script instead — see
Requirements.

**`devcontainer: command not found` after installing**
The standalone install script puts the binary in
`~/.devcontainers/bin`, which isn't on `PATH` by default:
```bash
echo 'export PATH="$HOME/.devcontainers/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

**`permission denied ... docker.sock`**
Your user isn't in the `docker` group. Docker Engine on Linux requires
this; Docker Desktop/OrbStack don't.
```bash
sudo usermod -aG docker $USER
newgrp docker          # or log out/in
```

## Versioning

This repo follows [Semantic Versioning](https://semver.org/) and keeps
a [CHANGELOG.md](CHANGELOG.md). The current version is also stamped
in `VERSION` at the repo root.

Because `devbox` bootstraps a project's `.devcontainer/` with a plain
file copy rather than a git submodule, that copy carries its own
`VERSION` file frozen at bootstrap time. `devbox <project-dir>`
compares it against the template's current version and tells you if
a newer template version is available — check CHANGELOG.md for what
changed, then re-bootstrap if you want it.

## License

MIT — see LICENSE.
