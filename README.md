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
