#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

echo "🛡️  Initializing Container Firewall..."

# 0. PRE-FLIGHT CHECK: Verify we are root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# 1. CLEANUP (Only Filter table, preserve NAT for DNS!)
# We explicitly DO NOT flush -t nat. Docker needs it for DNS (127.0.0.11).
iptables -F
iptables -X
# Create the ipset
ipset destroy allowed-domains 2>/dev/null || true
ipset create allowed-domains hash:net

# 2. RESOLVE & POPULATE (Do this BEFORE locking down)
echo "🔍 Resolving allowed domains..."

# Function to add IP to set safely
add_ip() {
    local ip="$1"
    # Check if valid IP/CIDR
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        ipset add allowed-domains "$ip" 2>/dev/null || true
    fi
}

# A. GitHub Ranges (Using jq to parse safely)
echo "   -> Fetching GitHub meta..."
gh_json=$(curl -s --connect-timeout 10 https://api.github.com/meta)
if [ -n "$gh_json" ]; then
    # Extract git, web, and api ranges. 
    # We use basic loops to avoid needing the 'aggregate' tool.
    for range in $(echo "$gh_json" | jq -r '.web[], .api[], .git[]'); do
        add_ip "$range"
    done
else
    echo "WARNING: Could not fetch GitHub IPs. Git operations might fail."
fi

# B. Specific Domains (NPM, Anthropic, VS Code)
# Note: IP-based filtering for CDNs is brittle, but this is the best effort.
DOMAINS=(
    "registry.npmjs.org"
    "registry.yarnpkg.com"
    "api.anthropic.com"
    "api.deepseek.com"
    "sentry.io"
    "marketplace.visualstudio.com"
    "vscode.blob.core.windows.net"
    "update.code.visualstudio.com"
    "deb.nodesource.com"
    "archive.apache.org"
    "repo.maven.apache.org"
    "github.com"
    "objects.githubusercontent.com"
)

for domain in "${DOMAINS[@]}"; do
    echo "   -> Resolving $domain..."
    # Get all A records
    for ip in $(dig +short "$domain" | grep '^[0-9]'); do
        add_ip "$ip"
    done
done

# 3. APPLY RULES (The Lockdown)
echo "🔒 Applying iptables rules..."

# A. ALLOW Loopback (Localhost) - Critical for internal processes
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# B. ALLOW DNS (UDP/TCP 53) - Critical for resolving anything
# We allow this outbound so the container can find IPs.
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -j ACCEPT

# C. ALLOW Established Connections (Responses to our requests)
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# D. ALLOW Target Domains (The Whitelist)
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# E. ALLOW inbound HTTP server on port 8080
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT

# F. DROP Policies (Block everything else)
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# 4. VERIFICATION
echo "✅ Firewall Active."
echo "   Testing connectivity..."

# Should FAIL
if curl --connect-timeout 2 https://www.google.com >/dev/null 2>&1; then
    echo "❌ ERROR: Firewall leaked! (Could reach Google)"
    exit 1
else
    echo "   Verified: Google is blocked."
fi

# Should SUCCEED
if curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "   Verified: GitHub is accessible."
else
    echo "❌ ERROR: GitHub blocked! Check your rules."
    exit 1
fi