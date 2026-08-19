# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.0] - 2026-08-19

Existing projects do not pick this up on their own. `devbox` only
bootstraps a `.devcontainer/` that isn't there yet, so to update one:

    rm -rf <project>/.devcontainer && devbox <project>

That rebuilds the image from the current template, which also refreshes
the agent CLIs installed by the features. Re-bootstrapping discards
everything else in that directory too, so copy aside anything you've
customised first: `firewall.d/` if you've edited the allowlist, and the
`Dockerfile` or `devcontainer.json` if you've added project-specific
tooling to them.

### Added

- `python3-pip` and `python3-venv` in the base image. `python3` was
  already there, but only as a transitive dependency of the credential
  proxy (mitmproxy), so it arrived with no `pip` at all and with
  `python3 -m venv` failing on a missing `ensurepip`. Nothing could fix
  that from inside a running container (`apt-get` needs root, and the
  only root access is three fixed no-argument scripts), which left any
  Python project in devbox stuck. A project can now build its own venv
  and install from PyPI, which the firewall has allowlisted all along.
  No project libraries are baked in, and no other language runtime is
  either: Node.js is still absent.
- `REQUESTS_CA_BUNDLE` in `devcontainer.json`'s `remoteEnv`, pointing at
  the system trust store. The credentials feature already exported it
  from `/etc/profile.d`, but that only covers login shells, and pip or
  `requests` talking through the credential proxy needs the proxy CA
  trusted in non-interactive processes too. Mirrors `NODE_EXTRA_CA_CERTS`,
  which is already set in both places.

### Changed

- Documented the image's actual toolset, in README (new "What's in the
  image") and in the `AGENTS.md` seeded into projects. Both now spell
  out that Debian marks the system interpreter externally managed
  (PEP 668), so a bare `pip install` failing is expected rather than a
  broken pip, and that `--break-system-packages` is the wrong way out:
  system site-packages is where the credential proxy's own dependencies
  live, and overwriting them can take credential injection down.
- README now documents how to add tooling to a single project (new
  "Adding tooling for one project"). The mechanism already existed, in
  that `devbox` only bootstraps a `.devcontainer/` that is missing and
  leaves an existing one alone, but nothing said so: a devcontainer
  feature in the project's own `.devcontainer/devcontainer.json`, then
  `devcontainer up --remove-existing-container` to force the rebuild
  that a config change alone doesn't trigger. Features are preferred
  over apt because bookworm freezes runtime versions (its `nodejs` is
  Node 18, end-of-life). The seeded `AGENTS.md` now points an agent at
  that same route rather than at a Dockerfile edit and a re-bootstrap.
- The seeded `AGENTS.md` carries those instructions in full, as a
  three-step recipe an agent can hand the user verbatim (edit
  `features`, rebuild with `--remove-existing-container`, verify), plus
  the reasoning it needs to answer follow-ups: why a feature beats apt,
  why installing one needs no allowlist change, and what to commit or
  copy aside. An agent asked "how do I get Node in here?" can now answer
  from the file instead of guessing, and knows not to report the missing
  runtime as a dead end.
- The seeded `AGENTS.md` also states which devbox version seeded it and
  links to <https://github.com/jozzian/devbox>, so an agent can point at
  the upstream docs and tell a stale copy from a current one.
  `.devcontainer/VERSION` stays authoritative for the version a project
  actually runs, because `AGENTS.md` is seeded once and never rewritten.
  A release now bumps the stamp in `AGENTS.md` alongside `VERSION`, per
  README's Versioning section.

## [0.2.2] - 2026-08-19

Existing projects do not pick any of this up on their own — `devbox`
only bootstraps a `.devcontainer/` that isn't there yet. To update one:

    rm -rf <project>/.devcontainer && devbox <project>

That rebuilds the image from the current template, which also refreshes
the agent CLIs installed by the features. Copy `.devcontainer/firewall.d/`
aside first if you've customised the allowlist — re-bootstrapping
discards it.

### Added

- `AGENTS.md` and `CLAUDE.md`, seeded at a project's root by
  `devbox <project-dir>` (only if the project doesn't already have its
  own, same as `firewall.d/`). Explains the sandbox's own constraints
  — firewall allowlist, no Docker inside the container, credentials
  injected via proxy rather than raw env vars, per-project persistent
  memory — to whatever agent runs inside it. `CLAUDE.md` is a thin
  pointer to `AGENTS.md` for Claude Code's lookup convention.

### Fixed

- `devbox <project-dir>` failed immediately for everyone with
  `ENOENT ... features/codex/devcontainer-feature.json`.
  `devcontainer.json` has referenced `./features/codex` since the very
  first commit, but `features/codex/` was listed in `.gitignore` from
  that same commit, so the directory was never actually tracked — a
  fresh clone had a dangling feature reference and nothing to satisfy
  it. Removed the `.gitignore` entry and committed the feature
  (installs the Codex CLI, same shape as `features/claude-code`).

- **Text could not be selected or copied out of Claude Code running in
  a devbox**, on host terminals without OSC 52 support (notably Apple
  Terminal). `devcontainer.json` now pins
  `CLAUDE_CODE_NO_FLICKER=0` in `remoteEnv` so the renderer choice is
  explicit rather than inherited.

  Established by a pty probe of the `claude` binary in the container,
  grepping the emitted byte stream for private-mode sequences:

  | `tui` config | `CLAUDE_CODE_NO_FLICKER` | alt screen + mouse |
  | --- | --- | --- |
  | unset | unset | no |
  | `fullscreen` | unset | no |
  | `fullscreen` | `0` | no |
  | `default` | unset | no |
  | unset | `1` | **yes** |
  | `fullscreen` | `1` | **yes** |

  `CLAUDE_CODE_NO_FLICKER=1` is the only input that enters the
  alternate screen (`?1049h`) and turns on mouse tracking
  (`?1000h`/`?1002h`/`?1003h`/`?1006h`). With mouse tracking on, the
  host terminal never sees a drag, so selection is impossible and a
  right-click is swallowed by the application instead of opening the
  context menu. The `tui` setting is inert for this purpose in both
  `~/.claude.json` and `~/.claude/settings.json`; do not rely on it.

  Claude Code's own select-to-copy does not rescue the fullscreen
  case: it writes the clipboard via OSC 52 plus a best-effort native
  `xclip`, and inside the container `DISPLAY` is empty so `xclip`
  fails, while Apple Terminal has no OSC 52 support. Both paths
  dead-end. Terminals that do support OSC 52 (Ghostty, iTerm2,
  WezTerm, kitty) can set `CLAUDE_CODE_NO_FLICKER=1` and use
  copy-on-select instead.

  Note this does not propagate to existing devboxes. `devbox
  <project-dir>` copies the template into the project's
  `.devcontainer/` at creation time, and `~/.claude.json` and
  `~/.claude` are bound per project directory
  (`~/.devbox/claude-json/<dir>.json` and the
  `devbox-claude-home-<dir>` volume). An already-created devbox keeps
  its snapshot until it is recreated.

### Removed

- `features/python/` — present since the initial commit but never
  referenced by `devcontainer.json` and never documented. Dead code,
  not a deliberate feature.

## [0.2.1] - 2026-08-18

### Fixed

- **`claude login` (and every other request) hung forever in projects
  upgraded to 0.2.0.** Seeding `.devcontainer/firewall.d/` was part of
  bootstrapping, and bootstrapping only runs when a project has no
  `.devcontainer/` at all — so a project that already had one picked up
  the new `init-firewall.sh` without ever getting a `firewall.d/` to
  read. The script treated the missing directory as "zero domains",
  leaving an allowlist of GitHub and DNS only. `devbox <project-dir>`
  now seeds `firewall.d/` whenever it is absent, independently of
  bootstrapping. An existing `firewall.d/` is never touched, so a
  trimmed allowlist stays trimmed.
- `init-firewall.sh` now exits non-zero when `firewall.d/` is missing
  instead of warning to stderr and carrying on. It previously went on
  to clear the fail-closed trap and write the readiness sentinel, so
  devbox reported a healthy sandbox that could not reach anything. A
  present-but-empty `firewall.d/` still only warns — trimming to
  nothing is a legitimate choice.
- Blocked egress is now `REJECT`ed rather than left to the `DROP`
  policy, so it fails immediately with "connection refused" instead of
  black-holing until the client times out. This is what made the bug
  above present as a frozen terminal with no output rather than an
  error; any future missing domain is now self-evident. The `DROP`
  policy remains as the backstop and as what `fail_closed` restores.
  IPv6 gets the same treatment so happy-eyeballs clients fall back to
  IPv4 at once instead of stalling.
- `DEVBOX_PROJECT_NAME` no longer picks up a trailing `-`. `tr -c`
  counted the newline from `basename` as out-of-set and rewrote it,
  so 0.2.0 renamed every project's `/home/node/.claude` volume and
  orphaned its stored login — which is why upgrading prompted a fresh
  `claude login` in the first place. The corrected name matches what
  0.1.x used, so upgrading from 0.1.x reattaches the original volume;
  anyone who ran 0.2.0 will need to log in once more.
- Bootstrapping no longer copies the template's own `.devcontainer/`
  into a new project, which nested a second, older config one level
  down.

### Added

- `claude.com` and `platform.claude.com` to the `claude-code` preset.
  `claude login`'s OAuth authorize and callback hosts were only ever
  reachable because they share an address with `claude.ai`.

## [0.2.0] - 2026-08-17

### Added

- File-based firewall allowlist: `init-firewall.sh` now reads every
  `.txt` file in a project's `.devcontainer/firewall.d/` (sorted,
  deduped) instead of a single hardcoded `network-policy.json` group
  list. Lets a project add or remove domains itself without patching
  devbox.
- `features/firewall/presets/` — a shared catalog of known domain
  needs (`base`, `github`, `claude-code`, `codex`, `socket`, `hermes`,
  `aliyun-modelstudio`), seeded from the previous hardcoded groups and
  split by tool/purpose.
- Bootstrap now copies `base` and `claude-code` presets into a new
  project's `.devcontainer/firewall.d/`, plus an empty, commented
  `99-custom.txt` for project-specific additions.
- `devbox firewall add <domain> [project-dir]`,
  `devbox firewall enable <preset> [project-dir]`,
  `devbox firewall list [project-dir]`, and
  `devbox firewall test <domain> [project-dir]` — manage a project's
  allowlist from outside the container, reloading a running
  container's firewall live via `docker exec ... init-firewall.sh`
  (no rebuild required).

### Changed

- `network-policy.json` now holds only `deny` and `allow_host_gateway`
  — the domain `groups` it used to carry moved to
  `features/firewall/presets/`.

### Removed

- The single-file `.devbox/allowed-domains` mechanism added in 0.1.5.
  Superseded by `.devcontainer/firewall.d/*.txt` (multiple files,
  presets, and the `devbox firewall` subcommands) after one day in the
  template with no other adopters to migrate.

## [0.1.5] - 2026-08-17

### Added

- `Codex CLI` README section documenting Codex CLI support: the
  `codex_apps` MCP server's `chatgpt.com` network requirement, and the
  expected/non-fatal bubblewrap sandboxing warning inside the
  container.
- Project-local `.devbox/allowed-domains` file, read by
  `init-firewall.sh`, so a project can allowlist a domain for a tool
  devbox doesn't know about yet without editing the vendored
  `network-policy.json`.

### Fixed

- Codex CLI's built-in `codex_apps` MCP server hung for 30 seconds and
  printed `MCP client for codex_apps timed out after 30 seconds` on
  every start: its `chatgpt.com` endpoint wasn't on the firewall
  allowlist, so the connection hung until Codex's own timeout gave up
  rather than failing fast. Added `chatgpt.com` to the `openai` group
  in `features/firewall/network-policy.json`.

## [0.1.4] - 2026-08-17

### Changed

- README "Agent memory persists per project" note now also covers
  login: Claude Code's OAuth token lives in
  `~/.claude/.credentials.json`, inside the same per-project volume as
  its memory, so logging in from one project folder doesn't carry
  over to a new one — only to that same folder on a later run.

## [0.1.3] - 2026-08-17

### Fixed

- Project folder names containing spaces or other characters Docker
  rejects (e.g. "rain alert") no longer break the Claude home volume
  mount. `devbox.sh` now sanitizes the folder's basename into
  `DEVBOX_PROJECT_NAME` and `devcontainer.json` builds the volume name
  from that instead of the raw `${localWorkspaceFolderBasename}`.

## [0.1.2] - 2026-08-16

### Added

- README "Security notes" section: allowlisted hosts can still be
  misused for exfiltration, injected credentials carry their full
  granted scope (not just what's needed), and agent memory (e.g.
  Claude Code's) persists per project in a Docker volume and can be
  poisoned by prompt injection from untrusted content read during a
  session.

## [0.1.1] - 2026-08-16

### Fixed

- Bootstrap no longer copies the template's `.git` directory into a
  project's `.devcontainer/`. Previously, `cp -r "$template_dir"
  .devcontainer` carried the template repo's full history and `origin`
  remote into every bootstrapped project, so a git command run from
  inside a project could silently operate on the template's own
  remote instead of the project's.

## [0.1.0] - 2026-08-16

### Added

- `devbox doctor` command and automatic preflight checks (`curl`, Docker
  installed/running, `docker` group membership, devcontainer CLI on `PATH`)
  run before every build, each failure printing an exact fix command.
- Troubleshooting section in the README covering `EBADENGINE`,
  `devcontainer: command not found`, and `docker.sock` permission errors.
- `VERSION` file and this changelog, so a project's bootstrapped
  `.devcontainer/` copy can be checked against the template's current
  version.

### Changed

- README Requirements now leads with the devcontainer CLI's standalone
  install script (bundles its own Node.js, avoids `EBADENGINE` on older
  system Node) and demotes `npm install -g @devcontainers/cli` to an
  alternative for users who already have a compatible Node version.
- Platform notes rewritten: Linux (Docker Engine) confirmed supported
  end-to-end on Ubuntu 24.04; OrbStack mentions scoped to macOS only.

[Unreleased]: https://github.com/jozzian/devbox/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/jozzian/devbox/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/jozzian/devbox/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/jozzian/devbox/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/jozzian/devbox/compare/v0.1.5...v0.2.0
[0.1.5]: https://github.com/jozzian/devbox/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/jozzian/devbox/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/jozzian/devbox/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/jozzian/devbox/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/jozzian/devbox/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/jozzian/devbox/releases/tag/v0.1.0
