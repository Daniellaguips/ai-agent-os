# .ai/LOCKS.md — active file/area claims

Held only while actively editing; released on commit or stop. Read this before
editing anything (agent-coordination.md §Start). Don't take over another agent's
*fresh* lock — coordinate or pick other work. Clear *stale* locks (branch gone /
worktree removed / old timestamp), noting it in JOURNAL.md.

Format:
`- [LOCKED] <glob/paths> — <agent> — <branch/worktree> — <ISO8601> — <what & why>`
Release: delete the line, or mark `[DONE] <ISO8601>`.

Prefer **one path per `[LOCKED]` line** when locking multiple files. If you
list several paths on one line, separate with commas or semicolons (not spaces
alone) so `ai-os-status.sh` can split them for OWNED matching.

---

(no active locks)
