#!/usr/bin/env bash
set -euo pipefail

# init-credentials.sh — Start credential-injecting HTTPS proxy.
# Runs as root via locked-down sudo at container start (postStartCommand).
# CA certificate generation and system trust store setup happen at build time
# in install.sh. This script only copies certs to the tmpfs and starts the proxy.

echo "Initializing credential injection proxy..."

MITMPROXY_HOME="/root/.mitmproxy"
CERT_STORE="/etc/devbox/mitmproxy"
PROXY_PORT=8080

# ── 1. Copy build-time certs to tmpfs-backed confdir ──────────────
mkdir -p "$MITMPROXY_HOME"
cp "$CERT_STORE"/* "$MITMPROXY_HOME"/ 2>/dev/null || true

# ── 2. Create audit log directory (on tmpfs) ──────────────────────
mkdir -p /var/log/devbox
chmod 755 /var/log/devbox

# ── 3. Start the proxy ─────────────────────────────────────────────
echo "Starting mitmdump on 127.0.0.1:$PROXY_PORT..."
mitmdump \
    --listen-host 127.0.0.1 \
    --listen-port "$PROXY_PORT" \
    --set confdir="$MITMPROXY_HOME" \
    -s /usr/local/lib/devbox/inject-credentials.py \
    -q &

# ── 4. Wait for proxy to be ready ─────────────────────────────────
for i in $(seq 1 50); do
    if ss -tlnp 2>/dev/null | grep -q ":$PROXY_PORT"; then
        echo "Credential injection proxy ready on port $PROXY_PORT."
        exit 0
    fi
    sleep 0.1
done

echo "WARNING: Proxy may not be ready yet (timeout waiting for port $PROXY_PORT)"
