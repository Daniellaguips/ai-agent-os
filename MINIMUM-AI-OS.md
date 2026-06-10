# Minimum Viable AI OS

Use this when adopting the system in a new repo before you need the full multi-agent
release cadence.

## 1. One Binding Contract

Every agent reads `~/.ai-os/AGENT-CONTRACT.md` first. It says what cannot be skipped:
coordination start check, no destructive DB changes without explicit approval, no
orphaned code, no deleting failing regression tests to go green, and no dirty-state
ambiguity at finish.

## 2. One State Command

Start and finish with:

```bash
~/.ai-os/bin/ai-os-status.sh
~/.ai-os/bin/ai-os-status.sh --finish
```

The command reports branch, worktrees, build/release markers, locks, handoff,
recovery, journal tail, and dirty files bucketed as `OWNED` or `UNKNOWN`. Do not start
new work or claim a clean finish while `UNKNOWN` remains.

When changing the hub itself, run:

```bash
~/.ai-os/bin/ai-os-validate.sh
```

For setup changes, run the full temp-home smoke:

```bash
~/.ai-os/bin/ai-os-validate.sh --smoke
```

## 3. One Local Coordination Folder

Each repo gets a gitignored `.ai/`:

- `LOCKS.md` — what an agent is actively touching.
- `HANDOFF.md` — what the next agent needs if this session stops.
- `JOURNAL.md` — non-obvious decisions and dead ends.
- `DIRTY.md` — explicit dispositions for dirty files that should not be committed yet.

Durable handoff still belongs in an issue tracker; `.ai/` is local working
memory.

## 4. One Release Rule

Every release has a named line and immutable marker. Regression review is always
previous marker -> candidate, never a guessed diff. If a line is debug-only, only
regression fixes, release blockers, failing-check fixes, and tests/docs proving those
fixes belong in it.

## 5. One Merge Gate

Before a spoke PR merges, run the three-stage QA gate:

1. QA-1: code/debug sweep.
2. QA-2: product intent check.
3. QA-3: regression sweep on the post-fix state.

Write the gate record and run `~/.ai-os/bin/ai-os-gate-check.sh <branch>` before the
merge.

## 6. One Learning Loop

When a bug or process failure escapes, add the durable rule where future agents read
it:

- product/runtime bug class -> project `.claude/debug-patterns.md`
- agent/process failure -> `~/.ai-os/lessons.md`
- recurring code correctness rule -> `~/.ai-os/coding-standards.md`
- gate ambiguity -> `~/.ai-os/qa-gate.md`

That is the whole core. Everything else in the hub is a stronger implementation of
these six pieces.
