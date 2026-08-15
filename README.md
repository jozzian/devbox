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

- Docker (Docker Desktop, OrbStack, or Docker Engine)
- Node.js + npm (for the devcontainer CLI)
- `npm install -g @devcontainers/cli`

## Install

```bash
git clone <YOUR_REPO_URL> ~/.devbox-template
echo 'source ~/.devbox-template/devbox.sh' >> ~/.bashrc   # or ~/.zshrc
source ~/.bashrc
```

## Use

```bash
devbox <project-dir>
```

First run on a directory with no `.devcontainer/` bootstraps one from
this template. Each project's copy is then independent — edits here
don't propagate to already-bootstrapped projects.

## Platform notes

Developed on macOS (OrbStack). Cross-platform support for Linux hosts
is in progress — see open issues.

## License

MIT — see LICENSE.
