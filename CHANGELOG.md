# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/jozzian/devbox/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jozzian/devbox/releases/tag/v0.1.0
