#!/usr/bin/env bash
set -euo pipefail

CODEX_USER="${_REMOTE_USER:-dev}"
echo "Installing Codex CLI for user: ${CODEX_USER}..."

if ! command -v curl &> /dev/null; then
    apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
        && apt-get clean && rm -rf /var/lib/apt/lists/*
fi

DEFAULT_INSTALLER_SHA256="ba92dd27e5c06f0d3bbc58bfa4b9cfb6599cd2742fbb1f92a2765e6c07dedb5a"

install_codex() {
    installer="$(mktemp /tmp/devbox-codex-installer.XXXXXX)"
    trap 'rm -f "${installer}"' EXIT
    curl -fsSL https://chatgpt.com/codex/install.sh -o "${installer}"
    chmod 0755 "${installer}"
    expected="${DEVBOX_CODEX_INSTALLER_SHA256:-${DEFAULT_INSTALLER_SHA256}}"
    if [ "${DEVBOX_ALLOW_UNVERIFIED_INSTALLERS:-0}" = "1" ]; then
        echo "Warning: running Codex installer without hash verification."
    elif ! printf '%s  %s\n' "${expected}" "${installer}" | sha256sum -c -; then
        echo "ERROR: Codex installer hash mismatch." >&2
        exit 1
    fi
    su - "${CODEX_USER}" -c "bash '${installer}'"
}

install_codex

if su - "${CODEX_USER}" -c 'command -v codex' >/dev/null 2>&1; then
    echo "Codex CLI installed successfully!"
    su - "${CODEX_USER}" -c 'codex --version' || true
else
    echo "Warning: codex not found on PATH after install."
fi
