# Workflows

How work moves from request to shipped without losing state or mixing unrelated
release risk. Project docs override this file on branch names, CI commands, deploy
markers, database ownership, and issue tracker conventions.

## Branch And Worktree Hygiene

- One substantial task gets one scoped branch and, when practical, one worktree.
- Start from the release trunk or the project integration branch named by the repo.
- Run `~/.ai-os/bin/ai-os-status.sh` before writing code.
- Do not stack unrelated work onto a dirty checkout. Classify every dirty path as
  ship, owned, scratch, generated, tracker-owned, or discardable before starting.
- Prefer branch/worktree names that mirror the task slug so `git worktree list` is
  readable.
- Never overwrite another agent's fresh lock or in-flight handoff.
- Run `~/.ai-os/bin/ai-os-prune.sh` at finish and clear stale worktrees you created.

## Commits

- Finished work should be committed before stopping unless the human explicitly
  asked for no commit.
- Run the project's relevant checks before committing: tests, typecheck, lint,
  invariant/regression suites, and stack-specific validators.
- Keep commits scoped. Avoid unrelated formatting, generated churn, or metadata
  changes.
- Commit messages should say what changed and what was verified.

## Pull Requests And Merge Gates

- Open the PR before pre-merge QA when the project uses the QA gate.
- Run the three-stage gate on the PR branch:
  - QA-1: code/debug sweep on the diff and changed contracts.
  - QA-2: product/intent QA against the original request or issue.
  - QA-3: regression QA after fixes.
- Record evidence in `.ai/qa-gate/<branch>.md` or the PR body.
- Run `~/.ai-os/bin/ai-os-gate-check.sh <branch>` before merging into a release or
  integration line.
- Merge only when checks are green or the human explicitly accepts a named risk.
- After merge, sync local trunk, delete merged branches, and remove temp worktrees.

## Release Lifecycle

Every shipped surface needs a named release line and immutable markers.

- Use one release line at a time per shipped surface.
- Every shipped stage gets an immutable marker: a tag, deploy SHA, release artifact,
  or another durable object the project can diff later.
- Regression diffs are always previous marker to candidate, never a guessed branch
  point.
- Debug-only stages contain regression fixes, failing-check fixes, release blockers,
  and tests/docs needed to prove those fixes. New product work waits for the next
  implementation stage unless it is the smallest viable fix for a concrete blocker.
- Non-affected surfaces can proceed separately only when the PR documents no impact
  on the frozen release artifact.
- Before opening the next implementation stage, review deferred issues and product
  decisions from the prior release.

Example marker scheme:

```text
build/<surface>-b<N>-impl
build/<surface>-b<N>-debug<k>
```

Use whatever names fit the project, but keep the invariants: explicit stage,
immutable marker, marker-to-candidate regression diff, and clean handoff.

## Integration Flow

Every final PR should state:

- touched surfaces,
- test accounts or fixture data,
- commands run,
- manual browser/device/API steps,
- expected database or admin state,
- expected final UI or API state,
- pass/fail evidence,
- blocked steps and owner.

Implementation stages document the full user/admin path. Debug-only stages rerun
the prior implementation flow and add targeted regression flows for fixed bugs.

## Database Changes

Assume the project database is production unless docs prove otherwise.

Never apply destructive schema or data changes without explicit in-session human
approval for that specific operation. Destructive means `DROP`, `TRUNCATE`, unsafe
`DELETE`, narrowing `ALTER`, `RENAME`, loosening constraints, or schema cleanup
believed to be unused.

Additive DDL is acceptable without special approval only when it is purely additive,
written as a migration in the repo, and paired with code/tests that use it in the
same change.

Read-only inspection is fine. If unsure whether an operation is destructive, ask.

## Documentation Edits

Project docs, standards, debug patterns, roadmap docs, and hub docs may be edited
through normal PR review. Keep pointer docs thin: central rules live in the hub, and
project-specific overrides live in project docs or project skill packs.

## Finishing Vs. Handoff

Finished means:

- committed,
- pushed,
- PR opened when applicable,
- gate/checks run,
- merged when green and permitted,
- local trunk synced,
- task branch/worktree cleaned,
- `ai-os-status.sh --finish` has no unexplained state.

Not finished means a tracker issue plus `.ai/HANDOFF.md` mirror containing branch,
worktree, PR, current status, failing checks, next command, owner, and regression
risk. Do not leave future work only in chat, a dirty branch, or a local note.

## Regression Watch

Adopt layers appropriate to the project:

- L0: anchor data from real escapes or known bug classes,
- L1: unit/invariant tests,
- L2: integration tests,
- L3: pre-merge QA gate,
- L4: post-ship monitoring and feedback,
- L5: every escaped regression becomes a test, pattern, lesson, or gate extension.

The rule is simple: a bug that escapes once should make the system better at catching
the whole class next time.
