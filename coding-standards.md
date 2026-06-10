# Coding Standards

House style, generalized from real multi-agent shipping projects. A project's own
`CODING-STANDARDS.md` is authoritative for that project; this is the default and the
thing to copy from when bootstrapping a new repo's standards file.

> **Living document — improved by the `qa-gate` self-improvement loop**
> (`~/.ai-os/qa-gate.md` §STAGE 4). When the pre-merge QA gate finds a recurring
> code-quality / correctness pattern a rule would have prevented, it promotes
> that **class** here (instance cited, deduped). Binds Codex and Claude
> equally. Project-specific variants go in that project's `CODING-STANDARDS.md`
> via a clean docs-spoke PR.

## Before writing any code

1. Read the project's `CODING-STANDARDS.md`, `.claude/debug-patterns.md`, and any
   architecture / data-ownership / roadmap doc its CLAUDE.md names. These encode
   decisions and past mistakes — follow them, don't re-derive or "simplify" them.
2. For frameworks that move fast, **don't trust training-data memory** — read the
   installed version's docs or the docs bundled in the repo before writing.
3. Check the roadmap before proposing architectural change — the work may already be
   a planned phase with a gating reason.

## When creating new functions

- **Wire to a caller in the same commit.** No orphaned code, ever — unreferenced
  code becomes destructive-by-cleanup later.
- Touches the DB → verify the table/column exists first.
- Needs new DB shape → write the migration in the same PR (see workflows §Database).
- Accepts user input → validate it (Pydantic `Field()` on the Python side; schema
  validation on the TS side). No unvalidated input reaches logic or the DB.
- Mutating endpoint → add auth + rate limiting.
- Add at least one test. For anything that has regressed before, an invariant test
  that names the rule (see below).

## Field-name / contract discipline

- Client field names MUST match the server schema exactly. Trace
  client → API handler → schema → DB column when in doubt.
- Rename a field in one place → grep and update every reference in the same change.
- Cross-service/repo contracts: both sides must agree on payload shape, auth, retry
  semantics, and status handling. Don't change one side alone.

## Scoring / matching / rules logic

General numeric-scoring defaults:

- Missing data = neutral (0.5), **never** a favorable default.
- Normalize **then** clamp — not clamp then normalize.
- Weights must sum to 1.0 — add an assert.
- Safety/abuse signals belong in a rules layer, not blended into preference weights.

## Mobile (React Native / Expo)

Defaults for React Native / Expo apps:

- State that persists across screens lives in context/store, not local `useState`.
- Persisted flags (AsyncStorage) are written **after** the server confirms, not before.
- Every `fetch` gets `AbortSignal.timeout(...)` (15000ms is the house default).
- Clean up intervals / subscriptions / listeners on unmount.

## Invariant & regression tests

- Every regression that has ever shipped gets a test that **names the rule and cites
  the PR** that established it, kept in a dedicated dir (e.g. `__tests__/*-invariants/`)
  with a README listing each rule + its PR.
- Every fix for an escaped regression must cite that test in the qa-gate record as
  `regression_test: <path[:line] or path::test>`. The path must resolve on disk so
  `ai-os-gate-check.sh` can prove the bug->test loop actually happened.
- Gate these in CI and ideally a pre-push hook so the feedback is fast.
- A failing invariant test is a signal to fix the code, **not** to delete the test.
  Retiring a rule (real product reason only) means updating the test, its README,
  and the PR description together in one PR — legible audit trail.

## Intentional weirdness

Some ugly-looking code is deliberate and load-bearing. If a doc, comment, or
debug-pattern says "this crash is harmless / do not remove this evasion / do not
'fix' this" — believe it, and don't regress it under a refactor.
If the project has a documented exception, verify the cited source before changing
it.

## Verify before you claim

Mirrors the debug team's rule. Every finding/claim about the code must be confirmed
by reading the actual code/schema/route/test output you cite — not a grep hit,
filename, or inference. A search match is a lead, not a fact. Recently-landed commits
move symbols; re-read the current file. A wrong claim costs more than a missing one.

## General correctness habits

- Handle edge cases explicitly: empty input, single item, missing/null fields.
- Concurrency: ask "can two requests corrupt shared state here?" before shipping
  anything that mutates shared rows/files/flags.
- Match the surrounding code's idiom, naming, and comment density. New code should
  read like it was always there.
