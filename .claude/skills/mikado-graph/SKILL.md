---
name: mikado-graph
description: Plans and tracks a complex refactoring using the Mikado Method. Trigger this skill when the user explicitly mentions "mikado." Also trigger when the user needs to incrementally plan or execute a refactoring or upgrade, untangle blockers before changing code, or visually track dependencies.
---

# Mikado Graph

The Mikado Method is an incremental refactoring technique: try a change, note what breaks, revert, then fix the blockers first. This skill tracks that process as a dependency graph — each node is a goal, a blocker, or a leaf task you can act on right now.

## Node types

| Shape           | Type        | Meaning                                           |
|-----------------|-------------|---------------------------------------------------|
| double-oval     | **goal**    | The root goal you want to achieve                 |
| rectangle       | **problem** | A blocking obstacle just discovered               |
| rect + orange   | **impact**  | Non-obvious side-effect needing migration/fix     |
| ellipse         | **todo**    | Leaf node -- actionable right now, no blockers    |
| any + gray      | done        | Completed, shown dashed + gray fill               |

Impact nodes (type=impact) are problems caused by non-obvious coupling:
DB columns storing class/field names, serialized JSON shapes, config keys,
event-sourcing event names, reflection-based lookups, generated code, etc.
They look like rectangles but with fillcolor="#ffe8cc" (orange tint) to signal
"this requires work outside the codebase".

## Execution protocol

When asked to execute a plan from a `plan_<slug>.md` file, follow the **try → fail → add → revert** loop:

1. Read `plan_<slug>.md` and identify all current leaf nodes (status=open, no open children, no open depends_on targets).
2. Pick one leaf. Attempt the implementation — make the code change.
3. Verify: run the test suite (or whatever verification is configured for this project).
4. **If verification fails:**
   a. **Revert the code change immediately** (e.g. `git checkout -- <file>`). The codebase must stay green. Do this BEFORE anything else.
   b. **Diagnose the root cause** — read the full failure output. Do NOT create a generic "tests fail" node. Identify the *specific* symptom using the table below and assign it the correct node type.
   c. **Create one node per distinct root cause.** If two tests fail for different reasons, add two separate child nodes.
   d. **Graph update sequence** (always in this exact order):
      1. Edit `plan_<slug>.md` — add the new child node(s) to the YAML.
      2. **Regenerate `plan_<slug>.dot`** by mechanically translating every node in the plan.md YAML into DOT syntax (apply shape/color rules from REFERENCE.md). Node IDs and labels are copied verbatim from the YAML — never invent or rename them. Overwrite the file completely; do not patch the old content.
      3. Render: `dot -Tsvg plan_<slug>.dot > plan_<slug>.svg`
      4. Save a versioned snapshot pair (see **Versioned snapshots** below).
   e. The current leaf is no longer a leaf (it now has open children). Start the loop again from step 1 with the new leaves.

**Failure → node-type classification table**

| Symptom in failure output                                          | Node type | Example label                                                       |
|--------------------------------------------------------------------|-----------|---------------------------------------------------------------------|
| Compile error / unresolved symbol after your change                | problem   | "Callers of `foo()` need update after rename"                       |
| Test assertion fails deterministically (expected X, got Y)         | problem   | "`OrderTest`: expected 3, got 0 — field not initialised"            |
| Identity vs. equality bug (`==` instead of `.equals()` / `===`)   | problem   | "Reference equality used where value equality required in predicate" |
| Off-by-one / boundary error                                        | problem   | "Loop iterates N+1 times — last element processed twice"            |
| Null / undefined dereference on code you didn't touch              | problem   | "Null receiver in `process()` — init sequence broken"               |
| Implicit type coercion producing wrong value                       | problem   | "String concatenated instead of added — missing numeric cast"       |
| Mutating shared state that other tests depend on                   | problem   | "Shared list mutated in test — later assertions see stale data"     |
| Test result differs across runs / flaky / order-dependent          | impact    | "Seed random number generator in test for determinism"              |
| Time-dependent test (clock, timestamp, expiry)                     | impact    | "Inject a fixed clock — test breaks near midnight"                  |
| Thread / concurrency ordering assumption                           | impact    | "Race condition in shutdown path — test passes only serially"       |
| Missing file / resource / config the test depends on               | impact    | "Approval baseline file missing — generate it first"                |
| External or DB state left dirty by a previous test run             | impact    | "DB not rolled back between tests — isolation broken"               |
| Reflection / serialization / RPC break (name changed)              | impact    | "Serialised type discriminator still uses old class name"           |
| Generated or derived artefact out of sync with source              | impact    | "Generated DTO not regenerated after field rename"                  |

For **non-determinism** (random, time, thread ordering): always classify as `impact` (orange node) — it is a hidden coupling to global mutable state outside the code under test. Label the node with the specific call site and what must be controlled (e.g. "Seed `random()` call in `checkout_test.py:88`").
5. **If verification passes:**
   a. Set the node's `status: done` in `plan_<slug>.md`.
   b. **Graph update sequence** (always in this exact order):
      1. **Regenerate `plan_<slug>.dot`** by mechanically translating every node in the plan.md YAML into DOT syntax (apply shape/color rules from REFERENCE.md). Node IDs and labels are copied verbatim from the YAML — never invent or rename them. Overwrite the file completely; do not patch the old content.
      2. Render: `dot -Tsvg plan_<slug>.dot > plan_<slug>.svg`
      3. Save a versioned snapshot pair (see **Versioned snapshots** below).
   c. Commit: the node label is the commit message. One node = one commit.
   d. Loop back to step 1.
6. Stop when the root goal node is the only remaining open node and all its children are done — then attempt the goal itself.

**Never fix a failure in-place and commit anyway.** A failing verification means the graph is incomplete — revert and grow the graph instead.

## Workflow

**Start a new graph**
User says: "I want to [goal]"
Derive a kebab-case slug from the goal (e.g. "Upgrade Postgres v3->v5" -> "upgrade-postgres-v3-v5").
Create and switch to a new git branch named `mikado/<slug>` before touching any files:
  git checkout -b mikado/<slug>
All plan files live under `.claude/mikado_output/<slug>/` (gitignored, no repo noise):
  mkdir -p .claude/mikado_output/<slug>
Create `.claude/mikado_output/<slug>/plan.md` with YAML frontmatter and `.claude/mikado_output/<slug>/plan.dot`.
Then render: dot -Tsvg .claude/mikado_output/<slug>/plan.dot > .claude/mikado_output/<slug>/plan.svg
Also save a versioned snapshot (see **Versioned snapshots** below).
Show the DOT content and confirm the SVG was written.

The plan.md file inside the slug directory is the machine-readable plan that agents
can discover and consume as a task list.

**Surface non-obvious impacts**
Whenever a new goal or problem node is added, proactively scan for hidden coupling
and add impact nodes for anything found. Ask the user to confirm before adding.
See REFERENCE.md "Impact checklist" for the full list of areas to probe.

**Discover a problem**
User says: "I tried [X], hit problem: [Y]" — or the agent's own verification fails during execution.
Apply the **Failure → node-type classification table** (see Execution protocol step 4b) to decide
whether the new node is a `problem` or `impact`. If X was a todo leaf, it is no longer a leaf.
Revert any partial change before continuing — the codebase must stay green.
Non-determinism (random, time, thread ordering) is always `impact` (orange node).

**Mark solved**
User says: "I solved [X]" or "done: [X]"
Set status: done on that node. Mark parent as actionable todo if all siblings are done.

**Link cross-dependencies**
User says: "[A] depends on [B]" or "[A] must happen before [B]"
Add B's id to A's depends_on list in the YAML. Render as a dashed arrow B -> A
(B must be done before A can start). These are peer dependencies, not parent-child.

**Show the graph**
User says: "render" or "show graph" or "update"
**Graph update sequence** (always in this exact order):
  1. **Regenerate** `.claude/mikado_output/<slug>/plan.dot` by mechanically translating every node in `plan.md`'s YAML into DOT syntax (apply shape/color rules from REFERENCE.md). Node IDs and labels are copied verbatim from the YAML — never invent or rename them. Overwrite the file completely; do not patch the old content.
  2. Render: `dot -Tsvg .claude/mikado_output/<slug>/plan.dot > .claude/mikado_output/<slug>/plan.svg`
  3. Save a versioned snapshot pair (see below).
Then show the full DOT block in the reply.

**Versioned snapshots**
Every time plan.dot is (re)written and rendered to SVG, also save numbered copies:
  Count existing snapshots: N = number of plan.vNNN.dot files in the slug dir
  Save: .claude/mikado_output/<slug>/plan.v<NNN+1 zero-padded to 3 digits>.dot  (copy of plan.dot)
        .claude/mikado_output/<slug>/plan.v<NNN+1>.svg  (rendered from the versioned dot)
This gives a full visual history of every graph state, one file pair per change.

## Rules

- `plan.md` is the **single source of truth** — always edit plan.md first, then regenerate plan.dot in full from it
- **Never patch plan.dot in-place.** Regenerate it completely from the plan.md YAML each time. Patching leaves stale content and produces the same SVG as before. Node IDs and labels are always copied verbatim from the YAML — never re-invented during regeneration.
- All plan files live under `.claude/mikado_output/<slug>/` (gitignored)
- Slug = kebab-case of the goal, max ~5 words, no special chars except hyphens
- Store the slug in the YAML frontmatter as field: slug
- Leaf nodes with status: open and no children -- render as ellipse (shape=ellipse)
- Non-leaf open nodes that have unresolved children -- render as rectangle (shape=rectangle)
- type=impact nodes -- shape=rectangle, fillcolor="#ffe8cc" (orange tint), tooltip="non-obvious impact"
- The root goal node -- shape=doublecircle
- Done nodes -- style="dashed,filled" fillcolor=lightgray
- Edges point from child to parent (child must be done before parent can be done)
- Cross-dependencies (depends_on) render as dashed arrows: dependency -> dependent  [style=dashed color=gray]
- A node is only a leaf (ellipse/actionable) if it has no open children AND no open depends_on targets
- Always show the full DOT block after any change, with filename as a comment header
- After writing plan.dot, immediately render SVG and save a versioned snapshot pair
- Tell the user the SVG was generated and its path
- Node ID prefix for impacts: I<n> (e.g. I1, I2) to distinguish from P<n> problems
- See REFERENCE.md for full data structure and DOT generation examples
