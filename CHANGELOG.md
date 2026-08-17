# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/jozzian/devbox/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/jozzian/devbox/compare/v0.1.5...v0.2.0
[0.1.5]: https://github.com/jozzian/devbox/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/jozzian/devbox/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/jozzian/devbox/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/jozzian/devbox/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/jozzian/devbox/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/jozzian/devbox/releases/tag/v0.1.0
