#!/usr/bin/env bash
set -euo pipefail

echo "Installing credential injection proxy dependencies..."

# Install mitmproxy (includes mitmdump) and CA certificate tools
apt-get update && apt-get install -y --no-install-recommends \
    mitmproxy ca-certificates sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/* 2>/dev/null || true

# Copy runtime scripts to stable locations (root-owned, not writable by dev)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
install -m 755 "$SCRIPT_DIR/init-credentials.sh" /usr/local/bin/init-credentials.sh
mkdir -p /usr/local/lib/devbox
install -m 644 "$SCRIPT_DIR/inject-credentials.py" /usr/local/lib/devbox/inject-credentials.py

# Create placeholder credentials config (populated at runtime via bind mount)
mkdir -p /etc/devbox
echo '{"credentials":[]}' > /etc/devbox/credentials.json
chmod 600 /etc/devbox/credentials.json

# ── Generate and install mitmproxy CA certificate at build time ────
# Certs are stored in /etc/devbox/mitmproxy/ (read-only at runtime) and
# copied to the tmpfs-backed /root/.mitmproxy at container start.
CERT_STORE="/etc/devbox/mitmproxy"
mkdir -p "$CERT_STORE"
timeout 3 mitmdump --set confdir="$CERT_STORE" -q 2>/dev/null || true

CA_CERT="$CERT_STORE/mitmproxy-ca-cert.pem"
if [ -f "$CA_CERT" ]; then
    cp "$CA_CERT" /usr/local/share/ca-certificates/devbox-proxy.crt
    update-ca-certificates 2>/dev/null
else
    echo "WARNING: Could not generate mitmproxy CA certificate at build time"
fi

# Write profile.d env vars for runtimes with custom trust stores
cat > /etc/profile.d/devbox-proxy-ca.sh << 'PROFILE'
# Credential injection proxy CA for runtimes with custom trust stores
export NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/devbox-proxy.crt
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
PROFILE

# Allow the remote user to run ONLY the credentials init script via sudo without a password
CRED_USER="${_REMOTE_USER:-dev}"
echo "${CRED_USER} ALL=(root) NOPASSWD: /usr/local/bin/init-credentials.sh" \
    > /etc/sudoers.d/credentials
chmod 440 /etc/sudoers.d/credentials

# Make sudoers readable by the dev user's group (avoids needing DAC_READ_SEARCH capability)
CRED_GROUP=$(id -gn "$CRED_USER" 2>/dev/null || echo "$CRED_USER")
chown root:"$CRED_GROUP" /etc/sudoers.d/credentials

# Disable sudo audit plugin if not already done (avoids needing AUDIT_WRITE capability)
if ! grep -q 'Plugin sudoers_policy' /etc/sudo.conf 2>/dev/null; then
    cat > /etc/sudo.conf << 'SUDOCONF'
# Only load policy and I/O plugins (skip audit to work without AUDIT_WRITE)
Plugin sudoers_policy sudoers.so
Plugin sudoers_io sudoers.so
SUDOCONF
fi

echo "Credential injection proxy feature installed successfully."
