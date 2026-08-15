#!/usr/bin/env bash
set -euo pipefail

PYTHON_USER="${_REMOTE_USER:-dev}"

echo "Installing Python and uv for user: ${PYTHON_USER}..."

apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-dev curl ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Pinned uv release: the versioned GitHub URL is immutable, so unlike the
# claude installer this pin never breaks on upstream releases — bump it
# deliberately to upgrade uv. Override the hash with
# DEVBOX_UV_INSTALLER_SHA256 (e.g. together with UV_INSTALLER_URL), or set
# DEVBOX_ALLOW_UNVERIFIED_INSTALLERS=1 to skip verification entirely.
UV_VERSION="${DEVBOX_UV_VERSION:-0.11.19}"
UV_INSTALLER_URL="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-installer.sh"
DEFAULT_INSTALLER_SHA256="ef8cf0575d37cf3c72e05f153dd72a845a87a7bb9be86184d5fe931b8c426250"

# Install uv
install_uv() {
    installer="$(mktemp /tmp/devbox-uv-installer.XXXXXX)"
    cleanup() {
        rm -f "${installer}"
    }
    trap cleanup EXIT

    curl -fsSL "${UV_INSTALLER_URL}" -o "${installer}"
    chmod 0755 "${installer}"

    expected="${DEVBOX_UV_INSTALLER_SHA256:-${DEFAULT_INSTALLER_SHA256}}"
    if [ "${DEVBOX_ALLOW_UNVERIFIED_INSTALLERS:-0}" = "1" ]; then
        echo "Warning: DEVBOX_ALLOW_UNVERIFIED_INSTALLERS=1; running downloaded uv installer without hash verification."
    elif ! printf '%s  %s\n' "${expected}" "${installer}" | sha256sum -c -; then
        echo "ERROR: uv installer hash mismatch for ${UV_INSTALLER_URL}." >&2
        echo "       Vet the new installer, then set DEVBOX_UV_INSTALLER_SHA256 to its sha256," >&2
        echo "       or set DEVBOX_ALLOW_UNVERIFIED_INSTALLERS=1 to skip verification." >&2
        exit 1
    fi

    su - "${PYTHON_USER}" -c "sh '${installer}'"
}

install_uv

# Make uv available system-wide via PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' > /etc/profile.d/uv.sh

mkdir -p /etc/fish/conf.d
echo 'fish_add_path -g ~/.local/bin' > /etc/fish/conf.d/uv.fish

echo "Python and uv installed successfully!"
