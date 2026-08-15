#!/usr/bin/env bash
set -euo pipefail

CLAUDE_USER="${_REMOTE_USER:-dev}"

echo "Installing Claude Code for user: ${CLAUDE_USER}..."

if ! command -v curl &> /dev/null; then
    apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
        && apt-get clean && rm -rf /var/lib/apt/lists/*
fi

# Known-good hash of https://claude.ai/install.sh, verified at template
# update time. Upstream rotating the script fails the build here on
# purpose: vet the new installer, then override with
# DEVBOX_CLAUDE_INSTALLER_SHA256, or set
# DEVBOX_ALLOW_UNVERIFIED_INSTALLERS=1 to skip verification entirely.
DEFAULT_INSTALLER_SHA256="cde4f1702d3b1695f92b73d26888364e17bca476e17f0fd676484c951d36c125"

install_claude_code() {
    installer="$(mktemp /tmp/devbox-claude-installer.XXXXXX)"
    cleanup() {
        rm -f "${installer}"
    }
    trap cleanup EXIT

    curl -fsSL https://claude.ai/install.sh -o "${installer}"
    chmod 0755 "${installer}"

    expected="${DEVBOX_CLAUDE_INSTALLER_SHA256:-${DEFAULT_INSTALLER_SHA256}}"
    if [ "${DEVBOX_ALLOW_UNVERIFIED_INSTALLERS:-0}" = "1" ]; then
        echo "Warning: DEVBOX_ALLOW_UNVERIFIED_INSTALLERS=1; running downloaded Claude Code installer without hash verification."
    elif ! printf '%s  %s\n' "${expected}" "${installer}" | sha256sum -c -; then
        echo "ERROR: Claude Code installer hash mismatch — upstream may have changed the script." >&2
        echo "       Vet the new installer, then set DEVBOX_CLAUDE_INSTALLER_SHA256 to its sha256," >&2
        echo "       or set DEVBOX_ALLOW_UNVERIFIED_INSTALLERS=1 to skip verification." >&2
        exit 1
    fi

    su - "${CLAUDE_USER}" -c "bash '${installer}'"
}

install_claude_code

# The installer places the binary in ~/.local/bin/ which isn't on PATH by
# default. Add it via the standard system-wide config for each shell.
echo 'export PATH="$HOME/.local/bin:$PATH"' > /etc/profile.d/claude-code.sh

mkdir -p /etc/fish/conf.d
echo 'fish_add_path -g ~/.local/bin' > /etc/fish/conf.d/claude-code.fish

if [ "$CLAUDE_USER" = "root" ]; then
    CLAUDE_HOME="/root"
else
    CLAUDE_HOME="/home/${CLAUDE_USER}"
fi
CLAUDE_BIN="${CLAUDE_HOME}/.local/bin/claude"
if [ -e "$CLAUDE_BIN" ]; then
    echo "Claude Code installed successfully!"
    "$CLAUDE_BIN" --version || true
else
    echo "Warning: Claude Code binary not found at ${CLAUDE_BIN}"
fi
