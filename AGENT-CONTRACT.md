# AI Operating Contract

You are one of several AI agents working on the same codebase. This contract is
always in context. Read it fully; follow it without being asked.

Hub: `~/.ai-os/` is the shared source of truth. Project docs override this hub on
project-specific details; the hub fills in the default workflow and safety rules.

## 1. Before You Touch Code

1. Run `~/.ai-os/bin/ai-os-status.sh`. This is the coordination check: branch and
   remote state, release/build markers, active locks, handoff, recovery files, and
   every dirty path bucketed as `scratch`, `OWNED`, or `UNKNOWN`.
2. Act on the result. A fresh lock or in-flight handoff on files you need means
   coordinate or pick different work. Pending recovery must be handled before new
   work. Any `UNKNOWN` dirty path needs a concrete disposition before starting.
3. Read the project coding standards, debug patterns, architecture, ownership, and
   roadmap docs named by the project.
4. If no `.ai/` dir exists and this is a git repo, run
   `~/.ai-os/bootstrap/init-project.sh` before substantial work.

## 2. Non-Negotiables

- **No destructive DB/schema changes without explicit in-session human approval.**
  Destructive includes `DROP`, `TRUNCATE`, unsafe `DELETE`, narrowing `ALTER`,
  `RENAME`, loosening constraints, and cleanup of schema believed to be unused.
- **No orphaned code.** New functions are wired to callers, new schema ships with a
  migration, new inputs are validated, mutating endpoints get auth/rate limits, and
  every meaningful change gets at least one test.
- **Never delete a failing invariant or regression test to go green.** Fix the code,
  or retire the rule deliberately with docs and review context.
- **Escaped regressions must close the loop.** The fix needs a regression test,
  debug pattern or lesson, and a QA-gate extension or tracked follow-up.
- **Do not "fix" documented intentional weirdness.** Verify claims by reading the
  cited code and docs, not by grep alone.
- **Finished means shipped or durably handed off.** Completed work is committed,
  pushed, reviewed/gated as the project requires, merged when green, and cleaned up.
  Unfinished work goes to the project issue tracker, not only chat or local notes.
- **No dirty-state ambiguity.** A session cannot end with unexplained tracked diffs,
  generated scratch, local config, stale worktrees, or unowned branches.

## 3. Coordination

- Take the narrowest `.ai/LOCKS.md` lock before editing files another agent could
  plausibly touch.
- Keep `.ai/HANDOFF.md` current while work is risky or multi-step.
- Append `.ai/JOURNAL.md` entries for non-obvious decisions, dead ends, and
  coordination facts the next agent could not infer from the diff.
- Anything that must survive a fresh clone belongs in the project issue tracker.
- If `.ai/recovery/*/RECOVERY.md` has `linear_status: pending` or equivalent
  tracker status, file/update the recovery issue before starting unrelated work.
- Before final response, run `~/.ai-os/bin/ai-os-status.sh --finish` and report
  active locks, handoff state, recovery state, dirty paths, branches/worktrees, and
  any tracked follow-ups.

## 4. Read-Order Map

| Doing | Read |
|---|---|
| Anything | this file, project coding standards, project debug patterns |
| Branching / committing / PR / DB | `~/.ai-os/workflows.md` |
| Writing code | `~/.ai-os/coding-standards.md` |
| Multi-agent work / locks / handoff | `~/.ai-os/agent-coordination.md` |
| QA sweep or release gate | `~/.ai-os/qa-gate.md` and project debug docs |
| Avoiding known process failures | `~/.ai-os/lessons.md` |

Tools to run instead of reimplementing:

```bash
~/.ai-os/bin/ai-os-status.sh
~/.ai-os/bin/ai-os-gate-check.sh <branch>
~/.ai-os/bin/ai-os-prune.sh
~/.ai-os/bin/ai-os-validate.sh
```

Per-project rules override this generic contract on project specifics. If the
conflict is unclear, ask before guessing.
