#!/usr/bin/env bash
set -euo pipefail

echo "Installing firewall dependencies..."

# Install iptables, ipset, jq, and sudo (for locked-down root execution).
#
# No dnsutils: init-firewall.sh resolves names with getent (glibc/nsswitch)
# rather than dig. Pulling in dig meant the whole bind9 suite -- bind9-libs,
# libxml2 and libicu72, 43 MB of which 35 MB is Unicode collation tables --
# to run two lookups per container start.
apt-get update && apt-get install -y --no-install-recommends \
    iptables ipset curl iproute2 jq sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/* 2>/dev/null || true

# Copy the firewall init script and network policy to stable locations (root-owned, not writable by dev)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
install -m 755 "$SCRIPT_DIR/init-firewall.sh" /usr/local/bin/init-firewall.sh
mkdir -p /usr/local/lib/devbox
install -m 644 "$SCRIPT_DIR/network-policy.json" /usr/local/lib/devbox/network-policy.json

# Allow the remote user to run ONLY the firewall script via sudo without a password
FIREWALL_USER="${_REMOTE_USER:-dev}"
echo "${FIREWALL_USER} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" \
    > /etc/sudoers.d/firewall
chmod 440 /etc/sudoers.d/firewall

# Make sudoers readable by the dev user's group (avoids needing DAC_READ_SEARCH capability)
FIREWALL_GROUP=$(id -gn "$FIREWALL_USER" 2>/dev/null || echo "$FIREWALL_USER")
chown root:"$FIREWALL_GROUP" /etc/sudoers /etc/sudoers.d /etc/sudoers.d/firewall

# Disable sudo audit plugin (avoids needing AUDIT_WRITE capability)
cat > /etc/sudo.conf << 'SUDOCONF'
# Only load policy and I/O plugins (skip audit to work without AUDIT_WRITE)
Plugin sudoers_policy sudoers.so
Plugin sudoers_io sudoers.so
SUDOCONF

echo "Firewall feature installed successfully."
