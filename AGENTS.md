# AGENTS.md

You are running inside **devbox**, a sandboxed devcontainer scoped to
this one project directory. This file was seeded automatically the
first time `devbox` set up this project (see `.devcontainer/README.md`
for how devbox itself works) -- edit or remove it freely, devbox never
overwrites an existing one.

## Network is allowlisted, not open

Outbound traffic is restricted to an explicit domain allowlist
(`.devcontainer/firewall.d/*.txt`). A request to anything not on that
list fails immediately with "connection refused" -- it will not hang,
so if something is timing out the firewall is not the cause, but if
it fails instantly that's the first thing to suspect.

You cannot fix this from inside the container yourself: adding a
domain requires running `devbox firewall add <domain>` or `devbox
firewall enable <preset>` on the **host**, outside this container. If
you hit a blocked domain, tell the user which one and ask them to run
one of those, rather than trying to work around the firewall.

`devbox firewall list` (run from the host) shows what's currently
allowed and why.

## No Docker inside this container

This container cannot build or run other containers -- there is no
Docker daemon or CLI inside it. If a task calls for `docker build`,
`docker run`, or similar, that has to happen on the host instead.

## Language toolchains are minimal, and you can't apt-get more

The image is `debian:bookworm-slim` plus a small fixed toolset:
`ca-certificates curl git jq less locales sudo vim python3-pip
python3-venv sqlite3 libsqlite3-dev unzip`. In practice:

- **Python works, but install into a venv.** `python3`, `pip` and
  `python3 -m venv` are all present. Debian marks the system
  interpreter as externally managed (PEP 668), so a bare `pip install
  <pkg>` fails with `error: externally-managed-environment` -- that's
  expected, not a broken pip. Create a venv instead: `python3 -m venv
  .venv && .venv/bin/pip install -r requirements.txt`.
- **Don't reach for `--break-system-packages`.** The system
  site-packages is where the credential-injection proxy's own
  dependencies live (mitmproxy runs on `/usr/bin/python3`), so
  overwriting them can take the proxy down, and with it every
  authenticated outbound request. A venv costs nothing here.
- **No Node.js and no other language runtime.** `node`, `npm`, and
  anything else language-specific are absent. The firewall does
  allowlist the npm, PyPI and crates registries, so a tool that
  bootstraps itself into `$HOME` still works -- there's just no system
  package to pull a runtime from.
- **No compiler toolchain.** No `gcc`, `build-essential`, or
  `python3-dev`, so a package with no prebuilt wheel for this platform
  will fail to build from source.

You can't extend this from in here: `apt-get` needs root, and the only
root access is the fixed no-argument scripts listed under Limited
privileges below. If a task genuinely needs another runtime or system
package, say which one and ask the user to add it to the image
(`.devcontainer/Dockerfile`) on the host and re-bootstrap.

## Credentials arrive injected, not as raw secrets

Environment variables like `ANTHROPIC_API_KEY` or `GH_TOKEN` are
present but empty placeholders -- real values are injected per-request
by a local proxy (`.devcontainer/features/credentials`), keyed off the
outgoing request's destination host, so the raw key never sits in
this process's environment. Printing one of these variables will not
reveal a usable secret; the proxy is what makes outbound requests to
allowlisted APIs actually authenticated.

Injection is opt-in per host and off by default. The proxy reads
`/etc/devbox/credentials.json`; a fresh project starts with
`{"credentials": []}` there, meaning *no* host has a credential wired
up yet -- that's the normal starting state, not a broken proxy. It's
fine to read that file to check what's configured; you don't need to
reverse-engineer the proxy to reach that conclusion.

You can't populate it yourself: it's bind-mounted read-only from
`~/.devbox/credentials/<project-folder-name>.json` on the **host**.
If a task needs a credential that isn't listed there, tell the user
which host is missing one and ask them to add an entry on the host in
the form `{"hosts": ["<host>"], "header": "Authorization", "value":
"Bearer <token>"}`, then restart the container. Same rule as the
firewall: don't hunt for a workaround, ask.

## GitHub push/PR access is not set up by default

The GitHub CLI (`gh`) is not installed in this image, and (per above)
no GitHub credential is injected unless the user has specifically
added one for `github.com`. In practice this means: don't assume you
can `git push`, open a PR, or create a repo from inside the container.

If a task needs that, check `/etc/devbox/credentials.json` for a
`github.com` entry first. If it's missing, say so plainly and ask the
user to either add one (see above) or run the git/gh command
themselves from the host -- don't spend time probing for alternate
auth paths, and don't assume `gh` is worth installing mid-task just
for one command.

## Your memory persists across sessions, per project

If you use a tool with its own long-term memory or login state (e.g.
Claude Code's `~/.claude`), it's stored in a Docker volume keyed to
this project folder's name, not wiped between runs. Anything written
there -- including content you were tricked into writing via a prompt
injection encountered during a session -- gets reloaded as trusted
context next time. Treat that persistence as a place to be careful,
not just a convenience.

## Limited privileges

Only a small, fixed set of scripts (`volume-init.sh`,
`init-firewall.sh`, `init-credentials.sh`) can run as root via sudo,
with no arguments accepted. There is no general root access and no
extra Linux capabilities beyond what the firewall itself needs
(`NET_ADMIN`/`NET_RAW`).
