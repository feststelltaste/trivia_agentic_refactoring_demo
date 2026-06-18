#!/bin/bash

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Skip plan/config files — only guard source edits
if [[ "$FILE_PATH" == *".claude/"* ]] || [[ "$FILE_PATH" == *"mikado_output"* ]]; then
  exit 0
fi

STAGED=$(git diff --cached --name-only 2>/dev/null)
MODIFIED=$(git diff --name-only 2>/dev/null)

if [ -n "$STAGED" ] || [ -n "$MODIFIED" ]; then
  echo "MIKADO GUARD: repo has uncommitted changes — revert or commit before making new edits."
  echo "The Mikado revert path (git checkout -- <file>) only works from a clean state."
  [ -n "$STAGED" ]   && echo "  Staged:   $STAGED"
  [ -n "$MODIFIED" ] && echo "  Modified: $MODIFIED"
  exit 2
fi
