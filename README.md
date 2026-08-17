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

- **Allowlisted hosts can still be abused.** The firewall (allowlist
  built from a project's `.devcontainer/firewall.d/*.txt` files, see
  Firewall below) blocks arbitrary destinations, not arbitrary *uses*
  of permitted ones. GitHub, the npm/PyPI/crates registries, and the
  Anthropic/OpenAI APIs are all allowlisted by default and all accept
  user-supplied content — a compromised or adversarial agent could
  still leak data via a public commit/gist, a published package, or a
  crafted API request. Trim `firewall.d/` to what a given project
  actually needs (`devbox firewall list` shows what's currently
  allowed and why).
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
  isn't part of the default bootstrap (only `base` and `claude-code` are
  copied in automatically — see Firewall below), so enable it once per
  project:
  ```bash
  devbox firewall enable codex
  ```
  If you still see the timeout after that, your project's bootstrapped
  `.devcontainer/` likely predates the `codex` preset entirely — check
  `devbox firewall list` to confirm `chatgpt.com` shows up, and re-run
  `devbox firewall enable codex` if not.
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

## Firewall

The firewall allowlist is file-based, not hardcoded. On container
start, `init-firewall.sh` reads every `.txt` file in the project's
`.devcontainer/firewall.d/` (sorted, deduped) and allows exactly those
domains, plus DNS, loopback, and GitHub's published IP ranges. Nothing
else gets out — same fail-closed, self-verified-on-every-start
behavior as before, just a configurable input instead of one hardcoded
list.

Bootstrapping a new project copies in a default set —
`base.txt` (package registries) and `claude-code.txt` (Anthropic API,
Claude Code telemetry) — plus an empty, commented `99-custom.txt` for
your own additions. Like the rest of bootstrapping, this is a one-time
copy: editing `features/firewall/presets/` here doesn't retroactively
change an already-bootstrapped project.

```bash
devbox firewall add <domain> [project-dir]      # append to 99-custom.txt, reload if running
devbox firewall enable <preset> [project-dir]   # copy a known preset in, reload if running
devbox firewall list [project-dir]              # show the resolved allowlist, grouped by file
devbox firewall test <domain> [project-dir]     # check reachability under current rules
```

`project-dir` defaults to the current directory. `add` and `enable`
reload a running container's firewall immediately via
`docker exec <container> sudo /usr/local/bin/init-firewall.sh` — no
rebuild needed.

**Available presets** (`features/firewall/presets/`):

| Preset | Domains | Default? |
| --- | --- | --- |
| `base` | `registry.npmjs.org`, `registry.yarnpkg.com`, `pypi.org`, `files.pythonhosted.org`, `crates.io`, `static.crates.io`, `index.crates.io`, `nodejs.org`, `iojs.org`, `bun.sh`, `registry-1.docker.io`, `auth.docker.io`, `production.cloudflare.docker.com` | **Yes** — bootstrapped into every new project |
| `claude-code` | `api.anthropic.com`, `claude.ai`, `console.anthropic.com`, `statsig.anthropic.com`, `sentry.io`, `o4507603601408000.ingest.us.sentry.io`, `api.statsig.com`, `featureassets.org` | **Yes** — bootstrapped into every new project |
| `github` | `github.com`, `api.github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com` | No — `init-firewall.sh` separately fetches GitHub's full IP ranges regardless, so this preset only matters as an A-record fallback if that fetch fails |
| `codex` | `api.openai.com`, `auth.openai.com`, `chatgpt.com` | No — `devbox firewall enable codex` if you use OpenAI's Codex CLI |
| `socket` | `api.socket.dev`, `socket.dev` | No |
| `hermes` | `hermes-agent.nousresearch.com` | No |
| `aliyun-modelstudio` | `dashscope-intl.aliyuncs.com`, `ws-5gd38sq7ojerxjn7.ap-southeast-1.maas.aliyuncs.com`, `token-plan.ap-southeast-1.maas.aliyuncs.com` | No |

Only `base` and `claude-code` are on by default — everything else needs
an explicit `devbox firewall enable <preset>` per project.

**Adding a new tool's domain:**
1. `devbox firewall test <domain>` — confirm it's actually blocked and
   not already covered by an existing preset.
2. `devbox firewall add <domain>` — allowlist it and reload.
3. Confirm the tool works.
4. Ideally, contribute it back: open a PR adding a
   `features/firewall/presets/<tool>.txt` to this repo, so the next
   person doesn't have to rediscover it.

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
devbox firewall add <domain> [project-dir]     # allowlist one more domain
devbox firewall enable <preset> [project-dir]  # allowlist a known tool's domains
devbox firewall list [project-dir]             # show what's allowed and why
devbox firewall test <domain> [project-dir]    # check reachability under current rules
```

See Firewall below for details on `devbox firewall`.

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

The firewall's allowlist is file-based (`.devcontainer/firewall.d/`,
see Firewall above) — this replaces any older instructions you may
have seen about editing `network-policy.json` or `init-firewall.sh`
directly to add a domain. Use `devbox firewall add`/`enable` instead.

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
