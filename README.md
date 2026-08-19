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

## What's in the image

`debian:bookworm-slim` plus a deliberately small, fixed toolset:
`ca-certificates curl git jq less locales sudo vim python3-pip
python3-venv sqlite3 libsqlite3-dev unzip`, and the agent CLIs the
features install (Claude Code, Codex). Nothing language-specific beyond
that, by design: a sandbox shouldn't presuppose the project's stack.

Python is the one partial exception. `python3` is in the image anyway
as a dependency of the credential proxy, so `python3-pip` and
`python3-venv` come along to make it actually usable. Debian marks the
system interpreter externally managed (PEP 668), so install into a venv
(`python3 -m venv .venv`) rather than system-wide; the system
site-packages is shared with the credential proxy's own dependencies,
and clobbering those breaks credential injection. Node.js is *not*
installed.

The firewall allowlists the npm, PyPI and crates registries by default
(see Firewall below), so once a project has a runtime, package installs
work without a firewall change. Adding a runtime or system package
means editing the template `Dockerfile` and re-bootstrapping. It can't
be done from inside a running container, which has no root beyond three
fixed no-argument scripts.

## Adding tooling for one project

Keep the template minimal and add what a single project needs to that
project. A project's `.devcontainer/` is a plain copy of the template,
and `devbox <dir>` only bootstraps it when it's missing, so anything you
put there stays put across sessions. That directory, not this repo's
`Dockerfile`, is where per-project tooling belongs.

Prefer a [devcontainer feature](https://containers.dev/features) over
apt. Debian bookworm's runtime packages are frozen at whatever version
shipped with the release, and for language runtimes that ages badly
(bookworm's `nodejs` is Node 18, already end-of-life), whereas a feature
installs the version you name. Add it to the project's
`.devcontainer/devcontainer.json`, alongside devbox's own local
features:

    "features": {
      "./features/claude-code": {},
      "./features/codex": {},
      "./features/credentials": {},
      "./features/firewall": {},
      "ghcr.io/devcontainers/features/node:1": { "version": "22" }
    }

Then rebuild that project's container once, from the host:

    devcontainer up --workspace-folder <project> --remove-existing-container

`--remove-existing-container` is the part that matters. `devbox` stops a
project's container when the session ends rather than deleting it, and a
plain `devcontainer up` will restart that container as-is, so a config
change alone doesn't get you a rebuild. After the one rebuild, go back
to using `devbox <project>` normally.

A feature installs while the image builds, which happens on the host
before the container's firewall exists, so pulling one needs no
allowlist change. Runtime traffic is separate: the npm, PyPI and crates
registries are allowlisted by default, and anything else the tool talks
to needs `devbox firewall add`.

Two things to keep in mind:

- Commit the project's `.devcontainer/` so the customisation is
  reproducible. This repo gitignores its own only because here it's a
  bootstrapped copy of the template rather than a project's config.
- Re-bootstrapping to pick up a newer template version (`rm -rf
  .devcontainer && devbox <project>`) discards these edits, the same way
  it discards `firewall.d/`. Copy the directory aside first and reapply
  your changes after.

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

## Agent instructions (AGENTS.md / CLAUDE.md)

The sandbox has its own constraints that whatever agent you run
inside it (Claude Code, Codex, ...) needs to know about to work
effectively — the firewall allowlist, no Docker inside the container,
credentials arriving via proxy injection rather than raw env vars, and
per-project persistent memory. `devbox <project-dir>` seeds an
`AGENTS.md` and a `CLAUDE.md` (a thin pointer to `AGENTS.md`, for
Claude Code's own lookup convention) at the project root explaining
these, the same way it seeds `firewall.d/` — only if the project
doesn't already have its own, and independent of bootstrapping, so an
already-bootstrapped project gets them too on its next `devbox` run.

If a project already has its own `AGENTS.md`/`CLAUDE.md`, devbox never
touches it — devbox's version is still copied into
`.devcontainer/{AGENTS,CLAUDE}.md` as part of the template, so you can
merge in whatever's useful by hand.

## Firewall

The firewall allowlist is file-based, not hardcoded. On container
start, `init-firewall.sh` reads every `.txt` file in the project's
`.devcontainer/firewall.d/` (sorted, deduped) and allows exactly those
domains, plus DNS, loopback, and GitHub's published IP ranges. Nothing
else gets out — same fail-closed, self-verified-on-every-start
behavior as before, just a configurable input instead of one hardcoded
list.

Blocked traffic is rejected, not dropped, so a request to a domain you
haven't allowlisted fails straight away with "connection refused"
rather than hanging until the client gives up. If a tool inside the
container stalls with no output, the firewall is not why — check
`devbox firewall list` and `devbox firewall test <domain>` anyway, but
expect an error rather than a freeze.

`devbox <project-dir>` copies in a default set — `base.txt` (package
registries) and `claude-code.txt` (Anthropic API, Claude Code
telemetry) — plus an empty, commented `99-custom.txt` for your own
additions. Unlike the rest of bootstrapping this isn't tied to first
run: any project without a `firewall.d/` gets one, so projects
bootstrapped before it existed are repaired on their next `devbox`.
A `firewall.d/` that already exists is left alone — trim it freely,
nothing is put back underneath you.

The contents are still a one-time copy: editing
`features/firewall/presets/` here doesn't retroactively change a
project that already has the preset. Use `devbox firewall enable
<preset>` to re-copy one.

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
| `claude-code` | `api.anthropic.com`, `claude.ai`, `claude.com`, `platform.claude.com`, `console.anthropic.com`, `statsig.anthropic.com`, `sentry.io`, `o4507603601408000.ingest.us.sentry.io`, `api.statsig.com`, `featureassets.org` | **Yes** — bootstrapped into every new project |
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
