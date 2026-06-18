#!/bin/bash

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only trigger on .java files
if [[ "$FILE_PATH" != *.java ]]; then
  exit 0
fi

PROJECT_DIR="$(pwd)"
APPROVED="$PROJECT_DIR/src/test/java/com/adaptionsoft/games/trivia/ApprovalTest.testApproval.approved.txt"
RECEIVED="$PROJECT_DIR/src/test/java/com/adaptionsoft/games/trivia/ApprovalTest.testApproval.received.txt"

# Bootstrap: if no approved file exists, generate and approve it automatically
if [ ! -f "$APPROVED" ]; then
  echo "APPROVAL TEST: No approved file found — bootstrapping golden master..."
  mvn test -Dtest=ApprovalTest -q > /dev/null 2>&1 || true
  if [ -f "$RECEIVED" ]; then
    cp "$RECEIVED" "$APPROVED"
    echo "APPROVAL TEST: Golden master created. Future edits will be compared against this snapshot."
  else
    echo "APPROVAL TEST: ERROR — could not generate received output. Check that the test compiles and runs."
  fi
  exit 0
fi

if mvn test -Dtest=ApprovalTest -q > /dev/null 2>&1; then
  echo "APPROVAL TEST: PASSED"
else
  echo "APPROVAL TEST: FAILED"

  DIFF=""
  if [ -f "$RECEIVED" ]; then
    DIFF=$(diff "$APPROVED" "$RECEIVED" || true)
    echo "--- approved"
    echo "+++ received"
    echo "$DIFF"
  fi

  # Spawn analysis sub-agent using the same API config as Claude Code
  if [ -n "$ANTHROPIC_AUTH_TOKEN" ] && [ -n "$ANTHROPIC_BASE_URL" ] && [ -n "$ANTHROPIC_MODEL" ]; then
    PROMPT="You are a Mikado failure analysis agent. An approval test just failed after a source file was edited.

Diff (approved vs received):
$DIFF

Classify this failure using the Mikado node-type taxonomy and return JSON only:
- type \"problem\": deterministic code bug (wrong logic, wrong value, wrong output structure)
- type \"impact\": non-obvious coupling (non-determinism, external state, serialisation, generated artefact out of sync)

Response format: { \"type\": \"problem\" | \"impact\", \"label\": \"<specific one-line description of the root cause>\" }"

    PAYLOAD=$(jq -n --arg model "$ANTHROPIC_MODEL" --arg content "$PROMPT" \
      '{model: $model, max_tokens: 256, messages: [{role: "user", content: $content}]}')

    ANALYSIS=$(curl -s "$ANTHROPIC_BASE_URL/v1/messages" \
      -H "x-api-key: $ANTHROPIC_AUTH_TOKEN" \
      -H "anthropic-version: 2023-06-01" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      | jq -r '.content[0].text // empty')

    if [ -n "$ANALYSIS" ]; then
      echo ""
      echo "FAILURE ANALYSIS (sub-agent): $ANALYSIS"
    fi
  fi
fi
