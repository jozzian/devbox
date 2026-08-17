#!/usr/bin/env bash
set -euo pipefail

# init-firewall.sh — Restrict outbound network to allowlisted domains.
# Runs as root via locked-down sudo at container start (postStartCommand).
#
# Structure matters for idempotency: all network lookups (DNS resolution,
# GitHub meta fetch) happen FIRST, while the previous run's rules — or the
# fresh container's default-ACCEPT policy — still permit them. Only then is
# the OUTPUT chain rebuilt. Fetch-after-flush would brick re-runs: with the
# policy already DROP, the GitHub fetch fails silently and the allowlist
# shrinks.

echo "Initializing firewall..."

POLICY_FILE="/usr/local/lib/devbox/network-policy.json"
GATEWAY_PORTS_DIR="/usr/local/lib/devbox/gateway-ports.d"
READY_SENTINEL="/run/devbox/firewall-ready"
# Project-local, user-editable extra domains — lets a project add a domain
# for a tool devbox doesn't know about yet without patching the vendored
# feature files. One domain per line; '#' comments and blank lines ignored.
EXTRA_DOMAINS_FILE="/workspaces/app/.devbox/allowed-domains"

# ── 0. Fail closed ──────────────────────────────────────────────────
# If we exit before reaching the end — a failed lookup, an iptables error,
# an `exit 1` from the IPv6 block — leave OUTPUT policy at DROP rather than
# whatever half-state we were in, and make sure no stale readiness sentinel
# survives. devbox refuses to trust a shell that believes it's sandboxed
# when the firewall never finished. The sentinel lives on tmpfs (/run), so
# it's recreated each start.
rm -f "$READY_SENTINEL" 2>/dev/null || true
fail_closed() {
    iptables -P OUTPUT DROP 2>/dev/null || true
    ip6tables -P OUTPUT DROP 2>/dev/null || true
    echo "ERROR: firewall init did not complete — egress left closed (fail-closed)." >&2
}
trap fail_closed EXIT

# ── 1. IPv6: close all egress, verified ─────────────────────────────
# The allowlist resolves IPv4 addresses only, so IPv6 must be fully
# blocked or every domain is reachable over AAAA records. A silently failing
# ip6tables call would leave the default ACCEPT policy in place and let any
# host be reached over IPv6, so apply, verify, and fall back to disabling
# IPv6 entirely — failing the whole script rather than running with IPv6
# open.
if [ -d /proc/sys/net/ipv6 ]; then
    ipv6_blocked=false
    if ip6tables -F OUTPUT 2>/dev/null \
        && ip6tables -A OUTPUT -o lo -j ACCEPT \
        && ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT \
        && ip6tables -A OUTPUT -d fd00:ec2::254/128 -j DROP \
        && ip6tables -P OUTPUT DROP \
        && ip6tables -S OUTPUT | grep -q -- '^-P OUTPUT DROP'; then
        ipv6_blocked=true
    elif sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 \
        && sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1; then
        echo "ip6tables unavailable; disabled IPv6 via sysctl instead"
        ipv6_blocked=true
    fi
    if [ "$ipv6_blocked" != "true" ]; then
        echo "ERROR: cannot enforce IPv6 egress blocking (ip6tables and sysctl both failed)" >&2
        echo "       Refusing to start with IPv6 egress unrestricted." >&2
        exit 1
    fi
fi

# ── 2. Resolve everything while egress still works ──────────────────

# DNS resolvers from resolv.conf. Loopback resolvers (Docker's 127.0.0.11)
# are covered by the loopback rule.
DNS_SERVERS=()
while read -r _ nameserver _; do
    case "$nameserver" in
        *.*) DNS_SERVERS+=("$nameserver") ;;
    esac
done < <(grep -E '^[[:space:]]*nameserver[[:space:]]+' /etc/resolv.conf 2>/dev/null || true)

# Build the new allowlist into a staging set and swap it in atomically at
# the end, so a re-run never leaves a half-filled live set.
ipset destroy allowed-domains-staging 2>/dev/null || true
ipset create allowed-domains-staging hash:net

# Allowed domains from the network policy
while IFS= read -r domain; do
    ips=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true)
    for ip in $ips; do
        ipset add allowed-domains-staging "$ip" -exist 2>/dev/null || true
    done
done < <(jq -r '.groups | to_entries[].value[]' "$POLICY_FILE")

# Extra domains a project has opted into via EXTRA_DOMAINS_FILE (see above).
if [ -f "$EXTRA_DOMAINS_FILE" ]; then
    while IFS= read -r domain; do
        domain="${domain%%#*}"                    # strip trailing comments
        domain="$(echo "$domain" | xargs || true)" # trim whitespace
        [ -n "$domain" ] || continue
        ips=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true)
        for ip in $ips; do
            ipset add allowed-domains-staging "$ip" -exist 2>/dev/null || true
        done
    done < "$EXTRA_DOMAINS_FILE"
fi

# GitHub IP ranges (supports HTTPS + git over SSH to GitHub)
GITHUB_META=$(curl -sf --max-time 10 https://api.github.com/meta 2>/dev/null || true)
if [ -n "$GITHUB_META" ]; then
    while read -r cidr; do
        ipset add allowed-domains-staging "$cidr" -exist 2>/dev/null || true
    done < <(echo "$GITHUB_META" \
        | grep -oP '"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+"' \
        | tr -d '"' \
        | sort -u)
else
    echo "  [WARN] could not fetch GitHub IP ranges; GitHub access may be limited to resolved A records"
fi

# Deny list: explicit drops that win over any allowlist entry. Hostnames are
# resolved now (before the chain is rebuilt); IPs/CIDRs pass through as-is.
DENY_TARGETS=()
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
        *[a-zA-Z]*)
            while IFS= read -r ip; do
                [ -n "$ip" ] && DENY_TARGETS+=("$ip")
            done < <(dig +short A "$entry" 2>/dev/null | grep -E '^[0-9]+\.' || true)
            ;;
        *)
            DENY_TARGETS+=("$entry")
            ;;
    esac
done < <(jq -r '.deny[]?' "$POLICY_FILE")

# Host gateway addresses: the default route plus whatever
# host.docker.internal maps to (Docker Desktop uses a separate address).
GATEWAY_ADDRS=()
default_gw=$(ip route | awk '/default/ {print $3}' | head -1)
[ -n "$default_gw" ] && GATEWAY_ADDRS+=("$default_gw")
while IFS= read -r ip; do
    [ -n "$ip" ] && GATEWAY_ADDRS+=("$ip")
done < <(getent ahostsv4 host.docker.internal 2>/dev/null | awk '{print $1}' | sort -u)

# Full host access only on explicit opt-in: the host's bound services
# (databases, Ollama, admin UIs) are exactly what a sandboxed agent should
# not reach by default. Features that need a specific host port declare it
# via a drop-in in gateway-ports.d instead.
ALLOW_HOST_GATEWAY=$(jq -r '.allow_host_gateway // false' "$POLICY_FILE")
if [ "$ALLOW_HOST_GATEWAY" = "true" ]; then
    for addr in ${GATEWAY_ADDRS[@]+"${GATEWAY_ADDRS[@]}"}; do
        ipset add allowed-domains-staging "$addr" -exist 2>/dev/null || true
    done
fi

GATEWAY_PORTS=()
if [ -d "$GATEWAY_PORTS_DIR" ]; then
    for f in "$GATEWAY_PORTS_DIR"/*; do
        [ -f "$f" ] || continue
        while IFS= read -r port; do
            case "$port" in
                '' | *[!0-9]*) continue ;;
            esac
            GATEWAY_PORTS+=("$port")
        done <"$f"
    done
fi

# ── 3. Rebuild the OUTPUT chain ─────────────────────────────────────

iptables -F OUTPUT 2>/dev/null || true

# Loopback
iptables -A OUTPUT -o lo -j ACCEPT

# Established and related connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# DNS to configured resolvers only
for dns_server in ${DNS_SERVERS[@]+"${DNS_SERVERS[@]}"}; do
    case "$dns_server" in
        127.*) continue ;;
    esac
    iptables -A OUTPUT -p udp -d "$dns_server" --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp -d "$dns_server" --dport 53 -j ACCEPT
done

# Cloud metadata endpoints (link-local range); the IPv6 IMDS endpoint is
# dropped in the IPv6 block above.
iptables -A OUTPUT -d 169.254.0.0/16 -j DROP

# Policy deny list — before any ACCEPT so it wins over the allowlist
for target in ${DENY_TARGETS[@]+"${DENY_TARGETS[@]}"}; do
    iptables -A OUTPUT -d "$target" -j DROP
done

# Feature-declared host gateway ports (e.g. clipboard bridge, Ollama)
for port in ${GATEWAY_PORTS[@]+"${GATEWAY_PORTS[@]}"}; do
    for addr in ${GATEWAY_ADDRS[@]+"${GATEWAY_ADDRS[@]}"}; do
        iptables -A OUTPUT -d "$addr" -p tcp --dport "$port" -j ACCEPT
    done
done

# Swap the staging allowlist into place and apply it
ipset create allowed-domains hash:net -exist
ipset swap allowed-domains-staging allowed-domains
ipset destroy allowed-domains-staging
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Default: drop everything else. IPv6 is handled in step 1 above.
iptables -P OUTPUT DROP

# ── 4. Verify ───────────────────────────────────────────────────────

echo "Firewall rules applied. Verifying..."

if curl -sf --max-time 5 https://api.github.com >/dev/null 2>&1; then
    echo "  [PASS] api.github.com reachable"
else
    echo "  [WARN] api.github.com not reachable — check rules"
fi

if curl -sf --max-time 3 https://example.com >/dev/null 2>&1; then
    echo "  [WARN] example.com reachable — firewall may not be working"
else
    echo "  [PASS] example.com blocked"
fi

# Signal success: rules are applied and the default policy is DROP. Clearing
# the trap first means an error after this point still won't masquerade as a
# clean run.
trap - EXIT
mkdir -p "$(dirname "$READY_SENTINEL")"
: > "$READY_SENTINEL"

echo "Firewall initialized."
