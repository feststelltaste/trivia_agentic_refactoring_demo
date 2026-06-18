#!/bin/bash
set -euo pipefail

CLAUDE_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SERVE_DIR="/workspace/.claude/viewer"

# Find the most recently modified JSONL transcript across all projects
LATEST=$(find "$CLAUDE_CONFIG/projects" -name "*.jsonl" 2>/dev/null \
  | xargs ls -t 2>/dev/null \
  | head -1)

if [ -n "$LATEST" ]; then
    cp "$LATEST" "$SERVE_DIR/latest.jsonl"
    echo "Auto-loading: $LATEST"
else
    echo "No transcripts found — drop a .jsonl file in the viewer manually."
fi

echo "Open: http://localhost:8080/transcript-viewer.html"
http-server "$SERVE_DIR" -p 8080 -c-1 --cors
