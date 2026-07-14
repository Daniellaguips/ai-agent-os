# Lessons

Process lessons live here after a real agent mistake or coordination failure. Keep
entries short, dated, and generalized: what happened, why it matters, and the rule or
tooling change that prevents the class next time.

Template:

```text
L<N> — YYYY-MM-DD — <short title>
What happened: <specific failure, stripped of sensitive/customer data>.
Why it matters: <risk to shipped work, handoff, data, or trust>.
New rule/check: <where the contract, workflow, validator, or skill now enforces it>.
```

Do not store credentials, customer facts, sensitive project details, or raw incident logs
here. Put long evidence in the project issue tracker and keep this file as the
portable rule index agents can safely read every session.

Lesson IDs in this public hub are their own sequence starting at `L1`. They do not
track any private fork's numbering. **Once an ID is assigned it is never renumbered** —
gates, tests, and code comments cite these IDs.

---

## L1 — 2026-07-14 — Half a loop is not a deliverable: every artifact needs its counterpart

**What happened.** One session surfaced the same disease from four unrelated angles, in
a real multi-agent project:

1. **29** human-reported build items in the tracker. Every one `state: captured`. Every
   one `pr: none`. The capture tooling — the *producer* — worked flawlessly. **Nothing
   had ever consumed the queue.** And the queue was not full of nice-to-haves: it
   included items the team had itself marked urgent. A queue with no drain is a very
   tidy way to never do the work while feeling organized about it.
2. A shipped, working user-facing capability was **silently deleted** by a layout-rewrite
   PR. No test asserted the capability, so nothing went red. It was gone for **two
   months**, and was found by a human using the product — not by any gate.
3. A human-reported bug was **deferred four times**, once because it *"needs a
   screenshot"* — an artifact the deferring agent could have produced itself in one
   command. The deferral reason was a task the agent was refusing to do.
4. A fix for a known dead-end state was written, reviewed, and then **parked on an
   unmerged branch** — while users hit the exact dead-end it was written to prevent. Its
   own spec said the product must never render that state.

**Why it matters.** In every case the artifact existed and looked finished. The capture
was captured, the code was written, the review was done, the spec was signed off. None
of it reached the running product. Work that never closes its loop is indistinguishable
from work that was never done — except that it also cost time and created a false record
that it was handled.

**Root cause.** Work is declared done when the **artifact** exists rather than when its
**loop closes**. The producer ships; the counterpart — caller, enforcing gate, queue
consumer, merge — never does.

And the reason it survives review: **every gate in a normal stack is addition-biased.**

| Gate | Why it passes anyway |
|---|---|
| typecheck | deleting a function *and* its only caller is perfectly valid code |
| tests | nothing ever covered the capability, so nothing goes red |
| code review | attention follows the `+` lines; the `-` lines are skimmed |
| product QA | asks "does this deliver the intent?", never "what did we LOSE?" |

So both silent capability deletion and never-built captures fail **OPEN** at every
layer. Nothing in the stack was ever pointed at the other half of the diff.

**The framing that produced the rule, verbatim:** *"we keep building stuff and it not
being enforced or merged — when you create something, part of the task is its
counterpart, taking a look at what calls it."*

**New rule/check.** `coding-standards.md` §The Counterpart Rule: every artifact ships
with its counterpart in the same PR — function→caller, endpoint→client+auth+test,
schema→migration, **rule→enforcing gate**, **queue→drain**, **spec→shipped code**,
**capability→a test that goes red when it is deleted**, **branch→merge or explicit
kill**. Before declaring done: *what calls this? what enforces this? what drains this?
what goes red if someone deletes this?* "Nothing" is a bug, not an answer.

Enforced mechanically, because a rule with no gate is exactly the failure this lesson
is about:

- `bin/ai-os-counterpart-check.sh` — flags functions added with no caller, and
  definitions deleted while no test file is touched (the layout-rewrite shape from
  incident 2). Escape hatches are explicit and leave a trail.
- `bin/ai-os-gate-check.sh` — every `decision: GO` record must now carry
  `counterpart:` (what closes the loop, resolving to a real path) and `removed:`
  (what this PR deletes, and what goes red for it). The gate now **asks**, which is
  the whole fix for addition bias.
- An agent may **not** defer a human-reported item; only the reporter may. *"Needs
  `<artifact the agent could produce>`"* is never a valid deferral reason.
- If your rules live in two places (a private hub and a public/shared copy), a change
  to one must propagate to the other — a stale shared copy is this same bug, one level
  up. This repo went a month behind its source hub while the source hub was busy
  learning this lesson.

**Related class:** a capture written into a void (a queue whose consumer, branch, or
file does not exist) is this same disease one layer down — the producer succeeds, the
loop never closes.
