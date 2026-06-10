---
name: ai-os-workflows
description: Run and improve shared AI operating-system workflows across coding agents, including release integration, debug-only sweeps, hub-and-spoke branching, DB/migration protocol, durable handoffs, dead-agent recovery, architecture audits, and reusable process lessons.
---

# AI OS Workflows

## Purpose

Use this skill when a task touches the shared workflow rather than only product code:
release integration, debug-only regression sweeps, DB or migration protocol,
multi-agent coordination, durable handoff, recovery, architecture flow audits, or
process self-improvement.

This skill does not replace the always-on contract. First read
`~/.ai-os/AGENT-CONTRACT.md` and run `~/.ai-os/bin/ai-os-status.sh`.

## Routing

- **Release/debug sweep:** follow `workflows.md` release lifecycle and `qa-gate.md`.
- **Integrator/merge work:** verify branch, release marker, checks, QA evidence, and
  cleanup before merging.
- **DB/schema/migration:** use the hard database protocol below.
- **Unfinished work/recovery:** create or update the project issue tracker and mirror
  short state in `.ai/HANDOFF.md`.
- **Multi-agent file ownership:** use `agent-coordination.md`.
- **Architecture flow audit:** trace the real runtime path before declaring a feature
  implemented, stubbed, dead, or safe to change.
- **Repeated process failure:** update `lessons.md`, a workflow doc, a validator, or
  a focused skill so future agents inherit the fix.

## Debug-Only Regression Sweep

1. Confirm the stage is debug-only and identify the previous shipped marker.
2. Diff previous marker to candidate.
3. Rerun the previous implementation flow.
4. Add targeted regression checks for each bug fixed in the debug-only stage.
5. Prioritize release blockers, changed contracts, known bug classes, adjacent
   read/write paths, auth/rate limits, schema boundaries, notifications, payments,
   and other side effects.
6. Fix the smallest viable regression. Defer redesigns, schema expansion, and
   product-direction questions to the tracker.
7. Promote repeatable checks into tests, scripts, or documented integration-flow
   steps before closing the release.

## Release Integrator

1. Verify the correct release or integration branch.
2. Merge scoped PRs only after their pre-merge QA gate is recorded and green.
3. Enforce the project's release cadence and marker scheme.
4. Verify migrations, contract changes, and deferred follow-ups are accounted for.
5. Merge only when checks are green or the human accepts a named risk.
6. After merge, sync trunk, create/verify the release marker, delete merged branches,
   remove temp worktrees, and record the outcome.

## DB And Migration Protocol

Assume the project database is production unless project docs prove otherwise.

Read-only inspection is fine. Additive DDL is allowed only when it is purely
additive, written as a migration in the repo, and paired with code/tests that use it
in the same change.

Destructive changes require explicit in-session human approval for that specific
migration or operation. Destructive includes `DROP`, `TRUNCATE`, unsafe `DELETE`,
narrowing `ALTER`, `RENAME`, loosening constraints, and schema cleanup believed to
be unused.

If unsure whether an operation is destructive, ask before running it.

## Durable Handoff And Recovery

For unfinished work, create/update the project issue tracker with branch, worktree,
PR, current status, ownership scope, blockers, failing checks, exact next command,
regression risk, and evidence. Mirror the short state in `.ai/HANDOFF.md`.

If `.ai/recovery/*/RECOVERY.md` has pending tracker status, file/update the recovery
issue, mark it filed, or close/delete it only after proving it was a false positive.

## Architecture Flow Audit

1. Read the architecture map and ownership docs.
2. Trace the real flow from UI/entry point through API/job/RPC/database/side effects
   and consuming UI.
3. Treat schema files, generated types, comments, and grep hits as leads, not proof.
4. Verify the runtime code and current schema before changing or deleting a path.
5. If duplicate stubs or misleading dead paths are found, remove them through the
   normal PR flow or file a tracker issue with regression risk.

## Self-Improvement Loop

Use this when the process was confusing, repeated, or failed.

- Product/runtime bug pattern: update project debug patterns or regression tests.
- Agent/process failure: update `~/.ai-os/lessons.md`.
- Repeated operational checklist: update this skill or create a focused skill.
- Project-specific source of truth: update project docs or a project pack.
- Unfinished work: create/update the tracker, not only chat or local notes.

Keep improvements concise and generalized. Include date, what happened, why it
matters, and the new rule/check.

## Done Criteria

- Requested workflow is complete or durably handed off in the tracker.
- Evidence is attached: commands, checks, PR/branch, screenshots/logs, row ids, or
  blocker details as applicable.
- `.ai/LOCKS.md` is released and `.ai/HANDOFF.md` is empty or current.
- Final response reports cleanup status, remaining dirty paths, branches/worktrees,
  active locks/handoffs/recovery, and tracked follow-ups.
