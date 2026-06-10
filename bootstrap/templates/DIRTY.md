# .ai/DIRTY.md — deliberately-kept dirty paths (gitignored, local)

The sanctioned place to register a dirty path as **intentionally kept**, so
`ai-os-status.sh` buckets it `OWNED` instead of `UNKNOWN` (exit 3). Use this
only for paths that are genuinely meant to stay dirty in this checkout
(local-only config, an in-flight experiment you own, scratch you will move out).
Anything that should ship goes through a scoped PR, not here. Anything another
agent owns belongs in `.ai/LOCKS.md`, not here.

Lessons L4: "Not mine" is not a disposition. Every line below states the path,
who owns it, and what happens to it (and when it stops being dirty).

Format — one per line:
`- <path or glob> — <owner> — <disposition: keep-local | move-out | discard-after X | experiment owned by ...> — <ISO8601>`

---

(no deliberately-kept dirty paths)
