#!/bin/bash
set -euo pipefail

echo "🚀 Running post-start setup..."

# 1. Fix permissions for mounted volumes
echo "   -> Fixing volume permissions..."
sudo mkdir -p /home/vscode/commandhistory
sudo chown -R vscode:vscode /home/vscode/commandhistory
chmod 755 /home/vscode/commandhistory
mkdir -p /workspace/.claude/state

# 2. Initialize firewall
echo "   -> Setting up firewall..."
sudo /usr/local/bin/init-firewall.sh

# 3. Add some danger in there
echo 'alias claude="claude --dangerously-skip-permissions"' >> ~/.bashrc

# 4. Configure git identity
echo "   -> Configuring git identity..."
git config --global user.email "agent@markusharrer.de"
git config --global user.name "Claude Code"

echo "✅ Post-start setup complete!"
