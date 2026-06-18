# Trivia — Agentic Refactoring Demo

This project demonstrates **agentic golden master testing**: a Claude Code agent refactors Java legacy code while a `PostToolUse` hook automatically verifies after every file edit that observable behavior has not changed.

The game used as the subject is the **Ugly Trivia** kata, originally created by [J.B. Rainsberger](https://github.com/jbrains/trivia) as a codebase for [Legacy Code Retreat](http://legacycoderetreat.jbrains.ca). It is intentionally messy and has no unit tests — a realistic starting point for practicing safe refactoring.

## What is a golden master test?

A golden master test captures the full output of a program and saves it as a "golden" snapshot. Future runs compare against that snapshot. If anything in the output changes — even a single character — the test fails.

This is especially useful for legacy code where there are no unit tests and the behavior is complex. You don't need to understand the logic; you just need the output to stay the same.

In this project, `ApprovalTest.testApproval` captures everything written to stdout by `GameRunner.main()` and compares it to `ApprovalTest.testApproval.approved.txt`.

## How the hooks work

Two hooks fire on every `Edit` or `Write` tool call, in sequence:

```
Agent edits a .java file
        │
        ▼
Hook 1: run-approval-test.sh  (type: command)
        │
        ├─ file is not .java? → exit silently
        │
        └─ file is .java
                ├─ no approved file yet? → bootstrap golden master automatically
                └─ approved file exists → run mvn test -Dtest=ApprovalTest
                        ├─ PASSED → print "APPROVAL TEST: PASSED"
                        └─ FAILED → print diff of approved vs received
        │
        ▼
Hook 2: analysis agent  (type: agent)
        │
        reads approved + received files
        │
        ├─ identical → { "ok": true }
        └─ differ    → { "ok": false, "reason": "<diagnosis>" }
                        e.g. "Chet escaped the penalty box one turn early —
                              likely due to the roll condition in Game.java:87"
```

The shell script gives raw speed. The agent hook adds intelligence: instead of handing the main agent a raw diff, it explains **what game behavior changed and which code is likely responsible**.

Both results are returned to the main agent as `additionalContext` before its next step.

## Key files

| File                                                                                 | Purpose                                                         |
| ------------------------------------------------------------------------------------ | --------------------------------------------------------------- |
| `.claude/settings.json`                                                              | Registers both hooks for `Edit` and `Write` tool calls          |
| `.claude/hooks/run-approval-test.sh`                                                 | Runs the approval test, bootstraps the golden master if missing |
| `src/test/java/com/adaptionsoft/games/trivia/ApprovalTest.java`                      | JUnit test that captures stdout and calls `Approvals.verify()`  |
| `src/test/java/com/adaptionsoft/games/trivia/ApprovalTest.testApproval.approved.txt` | The golden snapshot                                             |

## Prerequisites

- Java 21 and Maven installed
- `jq` installed (used by the hook script to parse JSON)
- Claude Code CLI installed

## Trying it out

### Step 1: Open the project in Claude Code

```bash
cd /workspace
claude
```

### Step 2: Ask the agent to refactor

Tell the agent something like:

> Refactor the `Game` class to extract the question-asking logic into a separate method.

**On the first Java file edit**, the shell hook bootstraps the golden master automatically:

```
APPROVAL TEST: No approved file found — bootstrapping golden master...
APPROVAL TEST: Golden master created. Future edits will be compared against this snapshot.
```

**On every subsequent edit**, if behavior is preserved:

```
APPROVAL TEST: PASSED
```

If behavior changed, the shell hook shows the raw diff and the agent hook explains what it means:

```
APPROVAL TEST: FAILED
--- approved
+++ received
-Chet was sent to the penalty box
+Chet's new location is 4

Hook analysis: Chet is no longer being sent to the penalty box after a wrong
answer. The wrongAnswer() method may have lost its penalty box assignment.
Check Game.java around the wrongAnswer() method.
```

### Testing the shell hook manually

You can invoke the shell script directly from the terminal without going through Claude Code:

```bash
# Simulate a Java file edit
printf '{"tool_input":{"file_path":"Game.java"}}' \
  | .claude/hooks/run-approval-test.sh

# Simulate a non-Java edit — should produce no output
printf '{"tool_input":{"file_path":"pom.xml"}}' \
  | .claude/hooks/run-approval-test.sh
```

### Seeing what's going on

**Session transcripts** — The devcontainer has `http-server` installed globally. The transcript viewer at `.claude/viewer/transcript-viewer.html` lets you inspect agent sessions in the browser, showing the full conversation, tool calls, and hook PASS/FAIL badges with color-coded diffs.

Use the helper script to auto-load the latest session transcript:

```bash
bash /workspace/.claude/viewer/start-viewer.sh
```

This copies the most recently modified JSONL transcript from the Claude state dir (`.claude/state/`) into `.claude/viewer/latest.jsonl`, starts `http-server` on port **8080**, and the viewer auto-fetches it on load. Open `http://localhost:8080/transcript-viewer.html` in your host browser.

**Mikado graph** — If the agent uses the `/mikado` skill to plan an incremental refactoring, it writes a dependency graph to `.claude/mikado_output/<slug>/`. The directory contains `plan.md` (machine-readable node list), `plan.dot` (Graphviz source), `plan.svg` (rendered graph), and versioned snapshots (`plan.v001.svg`, `plan.v002.svg`, …) capturing the graph after every change. Open any `.svg` directly in a browser to see where the refactoring stands.

## Why synchronous hooks?

Both hooks run synchronously, blocking the agent's next step until they complete. This is intentional: the agent needs the diagnosis _before_ it decides what to do next. An async hook would report results out of band, making it harder to correlate feedback with the edit that triggered it.

## Caveats about this codebase

_This section is why an agent is blocked from reading README.md_

### Randomness in GameRunner.java

`GameRunner.main()` uses `new Random()` without a fixed seed, so each run produces a different game sequence and different stdout output. This means the approval test will fail on every run after the golden master is bootstrapped — the captured output will never match the snapshot again.

The agent needs to recognize this and seed the RNG (e.g. `new Random(42)`) before the golden master approach becomes useful. This is an intentional first challenge: the agent must stabilize the output before refactoring can be safely guarded by the test.

### `assertTrue(false)` in SomeTest.java

`SomeTest.true_is_true()` contains a hardcoded `assertTrue(false)` — it always fails. The approval hook avoids this by running only `-Dtest=ApprovalTest`, so it does not surface during normal agentic refactoring. However, if the agent runs the full test suite (e.g. `mvn test`), it will see a failing test that has nothing to do with its changes. The agent may get confused and try to "fix" it, which is a distraction. Left in deliberately as a piece of realistic legacy noise.

### Typos in game output

`Game.java` prints `"Answer was corrent!!!!"` — a typo that is baked into the approved golden master snapshot. If the agent "helpfully" corrects the spelling to `"correct"` during a refactoring, the approval test will fail. The agent must learn to treat the golden master as the source of truth and preserve existing output character-for-character, typos included.

## Limitations

- **Maven startup overhead:** Each hook invocation starts a fresh Maven process (~2–4 seconds). Two complementary open-source options can reduce this: the **Maven Daemon** (`mvnd`) keeps a warm JVM between builds and eliminates cold-start time; the **Takari Lifecycle plugin** (`io.takari.maven.plugins:takari-lifecycle-plugin`) replaces the standard compiler plugin with genuine incremental compilation, only recompiling changed classes. These address different bottlenecks — daemon for JVM startup, Takari for compilation time — and can be combined.
- **Agent hook latency:** The analysis agent adds an LLM call on top of Maven startup. For a fast edit loop, this is a trade-off for richer feedback.
- **Single test scope:** The hook only runs `ApprovalTest`. If you add other tests, adjust the `-Dtest=` argument or remove it to run the full suite.

## Note on AI familiarity with this kata

The Ugly Trivia game is widely used in training materials and conference workshops. AI models may have seen it during training and produce suspiciously clean refactorings as a result — not representative of how an agent would behave on genuinely unfamiliar legacy code. This repo is a showcase of the technique, not a benchmark of agent capability.

## License

The Ugly Trivia game is the original work of [J.B. Rainsberger](https://github.com/jbrains/trivia) and contributors, licensed under the **GNU General Public License v3.0**. The agentic testing setup in this repository is released under the same license. See [LICENSE.txt](LICENSE.txt) for the full text.
