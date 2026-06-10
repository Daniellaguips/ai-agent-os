# QA Gate

Canonical pre-merge three-stage QA runbook for Claude, Codex, Cursor, or any other
agent using this hub. Project docs may specialize commands and release markers, but
the stages and evidence rules stay the same.

## When

Run this gate before any spoke PR merges into an integration branch, release branch,
or other build line. Open the PR first, run the gate on the PR branch, fix blockers,
then merge. Never merge first and sweep afterward.

A docs-only PR with no code, product, or regression surface may be marked N/A, but
the N/A decision must still be recorded.

## Inputs

Gather before judging:

1. PR number, branch, or diff range.
2. Exact diff base: previous shipped marker to candidate, or `none — first build`.
3. Touched issue tracker items and the original intent.
4. Changed surfaces and adjacent contracts.
5. Baseline commands for the stack.
6. Integration flow or release checklist for the touched path.

## QA-1: Code / Debug Sweep

Review the diff in risk order:

- changed contracts and callers,
- known debug-pattern classes,
- adjacent read/write paths,
- auth, rate limits, schema, payment, notification, jobs, file/storage, and other
  side-effect boundaries,
- exploratory checks only after the high-risk paths are clean.

Every finding needs repro or evidence, expected vs actual behavior, affected
surface, severity, and whether it blocks merge. Verify claims against primary source
files or command output.

## QA-2: Product / Intent QA

Check whether the PR delivers the requested intent end to end as the user or admin
experiences it. Compare against the issue, original request, screenshots, acceptance
criteria, and project docs. A technically correct implementation can still fail
intent.

Classify each gap as blocker, non-blocker follow-up, or needs human decision.

## Fix Loop

Fix blockers before merging. Each substantial fix may need its own scoped PR and
gate. Non-blockers go to the tracker with disposition. Auto-fix simple clear issues
when safe; defer only with a concrete reason and owner.

## QA-3: Regression QA

After fixes, rerun the risk sweep on the post-fix state. Use previous shipped marker
to candidate as the regression diff. Rerun the relevant integration flow and add
targeted regression checks for each fixed bug.

Confirm whether any finding is a new regression, a pre-existing limitation, or a
separate follow-up.

## Evidence Record

Write `.ai/qa-gate/<branch>.md` and paste the same block into the PR body when a PR
exists. One `key: value` per line:

```text
pr:               <#|url|local-only>
diff_base:        <previous shipped marker> | none — first build
baseline:         pytest=<PASS|n/a> tsc=<PASS|n/a> lint=<PASS|n/a>
qa1:              <GO | finding summary, no blockers>
qa2:              <GO | finding summary, no blockers>
qa3:              <GO> (post-fix; required for GO)
integration_flow: <path to flow doc> | n/a — docs-only
regression:       no | yes — <ticket/source>
regression_test:  n/a | <path[:line] or path::test> — failed pre-fix
debug_pattern:    n/a | <path#Pattern N>
gate_extension:   n/a | same-pr:<path> | tracker:<id> regression-watch:extend-gates | not-needed:<why>
decision:         GO | N/A — docs-only | NO-GO
signoff:          qa3-clean | human-accepted: "<quote>"
rationale:        <required iff decision is N/A — docs-only>
```

A GO record must classify `regression:`. If `regression: yes`, the gate checker
requires:

- a real `regression_test:` path,
- a numbered `debug_pattern:` path,
- a `gate_extension:` of `same-pr:<path>`, `tracker:<id> regression-watch:extend-gates`,
  or `not-needed:<why>`.

Run before merge:

```bash
~/.ai-os/bin/ai-os-gate-check.sh <branch>
```

## Stage 4: Self-Improvement

After GO/NO-GO, route every finding or gate miss by class:

| Signal | Durable home |
|---|---|
| Bug class the debug team should catch | project debug patterns or regression tests |
| Agent/process failure | `~/.ai-os/lessons.md` |
| Recurring code-quality/correctness rule | `~/.ai-os/coding-standards.md` or project standards |
| Gate ambiguity or missed check | this file |
| Product/spec follow-up | project issue tracker |

Promote only generalizable classes. Cite the concrete instance in the tracker or PR,
dedupe against existing rules, and keep the durable rule concise.
