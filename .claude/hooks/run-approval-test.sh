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
  if [ -f "$RECEIVED" ]; then
    echo "--- approved"
    echo "+++ received"
    diff "$APPROVED" "$RECEIVED" || true
  fi
fi
