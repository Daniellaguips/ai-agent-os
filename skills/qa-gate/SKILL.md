---
name: qa-gate
description: Run the mandatory pre-merge 3-stage QA gate with QA-1 code/debug sweep, QA-2 product intent QA, and QA-3 regression QA on the post-fix state before a PR merges into an integration or release line.
---

# QA Gate Skill

This skill is a thin wrapper. **Read and execute `~/.ai-os/qa-gate.md`** — that
is the single source of truth (Codex follows the same file; do not let this
skill drift from it). Read it fully each run; it may have been updated.

## Procedure

1. Gather inputs from `qa-gate.md`: PR/diff, previous shipped marker, touched
   tracker items, intent, changed surfaces, baseline commands, and integration flow.
2. Run QA-1 code/debug sweep and QA-2 product intent QA on the PR branch.
3. Fix blockers; route non-blockers or decisions to the tracker.
4. Run QA-3 regression QA on the post-fix state.
5. Write the evidence record in `.ai/qa-gate/<branch>.md` and the PR body.
6. Run `~/.ai-os/bin/ai-os-gate-check.sh <branch>` before merge when acting as
   integrator.
7. Record docs-only N/A decisions instead of skipping silently.

## Self-Improvement

Classify each finding or gate miss by class and route it to debug patterns,
regression tests, `lessons.md`, `coding-standards.md`, this runbook, or the
project tracker. Promote only generalizable classes and cite the concrete instance.

End with the cleanup/status note required by `AGENT-CONTRACT.md`: branches,
worktrees, pending items, tracker follow-ups, and any standard/pattern/lesson/runbook
promotion made this run.
