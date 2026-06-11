# Agent Coordination

How multiple AI agents work in the same repo without clobbering each other. The
protocol is tool-agnostic: every agent reads and writes plain Markdown under the
repo's local `.ai/` directory.

| Layer | Lives in | Lifespan | Purpose |
|---|---|---|---|
| Scratch | repo `.ai/` | this session to next local session | locks, handoff, journal, dirty-state notes |
| Durable handoff | issue tracker | until shipped | work that must survive a fresh clone or machine |
| Shared rules | `~/.ai-os/` | ongoing | standards, lessons, workflows, skills |

`.ai/` is gitignored on purpose. Anything important outside this machine belongs in
the project issue tracker.

## `.ai/` Files

- `JOURNAL.md`: append-only notes for non-obvious decisions, dead ends, and facts
  the next agent cannot infer from the diff.
- `LOCKS.md`: active claims on files or areas. Release locks when done or stopped.
- `HANDOFF.md`: overwritten state for in-flight work on this machine.
- `DIRTY.md`: explicit owner/disposition notes for dirty paths that must remain.
- `recovery/`: watchdog output for abandoned work.

## Start Check

Run this first in every session:

```bash
~/.ai-os/bin/ai-os-status.sh
```

It reports branch/remotes, release markers, locks, handoff, journal tail, recovery,
and dirty-path buckets. If it exits non-zero, resolve the reported condition before
starting unrelated work.

Required dispositions for dirty paths:

- ship through the current task,
- claim with a lock or `DIRTY.md`,
- move out as local scratch,
- assign to an issue/branch/worktree,
- or discard only when you are sure it is not another agent's work.

"Not mine" is not a disposition.

## Locks

Prefer the atomic primitive — editing `LOCKS.md` by hand races (two agents both
read "no lock" and both append, and the whole-file edit is a lost update):

```text
bin/ai-os-lock.sh acquire <path-or-glob> "why"   # mkdir-atomic; exit 3 if held by a live owner
bin/ai-os-lock.sh release <path-or-glob>          # on commit or stop
bin/ai-os-lock.sh list                            # active locks (+ DEAD markers)
bin/ai-os-lock.sh reap                            # release dead-owner / TTL-expired locks
```

It serializes the `LOCKS.md` mirror under an index lock and reclaims locks whose
owner died, so status tooling and humans keep reading `LOCKS.md` as before. As a
manual fallback, append the narrowest useful lock yourself:

```text
- [LOCKED] <path-or-glob> — <agent> — <branch/worktree> — <ISO8601> — <why>
```

Use one path/glob per line when possible. If a line names multiple paths, separate
them with commas or semicolons so status tooling can classify ownership.

Rules:

- Do not edit through another agent's fresh lock.
- A scoped worktree/branch is the strongest lock for substantial work.
- Release the lock when committed, merged, or durably handed off.

## Handoff

Use `.ai/HANDOFF.md` for local continuation state. If work will outlive the current
session or matters to another machine, create/update a tracker issue with:

- branch and worktree path,
- PR link if any,
- current status,
- failing checks or blockers,
- exact next command,
- ownership scope,
- regression risk,
- evidence gathered so far.

Then mirror the short version in `.ai/HANDOFF.md`.

## Journal

Append a line for facts that matter later:

```text
YYYY-MM-DDTHH:MMZ <agent> — <decision, dead end, risk, or coordination fact>
```

Skip routine narration. Record decisions and failed paths that would cost the next
agent time to rediscover.

## Recovery

The watchdog may write `.ai/recovery/<stamp>/RECOVERY.md` if an agent appears to
have died with uncommitted work or an in-flight handoff. At session start:

1. Read the recovery file.
2. File/update the matching tracker issue if its tracker status is pending.
3. If it is a false positive because the work resumed or already shipped, close the
   issue as a false positive and remove the recovery state.
4. Restore captured work only when it belongs to your task.

Recovery files are non-destructive snapshots. Do not delete them without either
filing the tracker issue or proving they are false positives.

## Shared Browser Or UI Resources

If a browser profile, simulator, local server, or desktop app state is shared, treat
it like a file. Add a lease in `LOCKS.md`:

```text
- [LOCKED] browser:<backend>:<profile-or-purpose> — <agent> — <branch/worktree> — <ISO8601> — <site/task>
```

List tabs or sessions fresh at task start. Do not reuse stale tab ids, handles,
snapshots, or UI element ids from earlier sessions. Release the lease when done.

## Finish Report

Before final response, run:

```bash
~/.ai-os/bin/ai-os-status.sh --finish
~/.ai-os/bin/ai-os-prune.sh
```

Report:

- pending work,
- active locks,
- in-flight handoff,
- recovery files,
- dirty paths and their disposition,
- branches/worktrees left behind,
- tracker or human follow-ups.

A clean finish has no unexplained `UNKNOWN` dirty paths and no stale worktree from
the current task.
