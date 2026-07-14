# AI Agent OS

Portable operating-system rules for AI coding agents working in real repositories.
The hub gives Claude Code, Codex, Cursor, and similar tools one shared contract,
one coordination protocol, and executable checks for state, handoff, QA evidence,
clean-machine setup, and a bundled debug-agent team.

This public edition is designed to be shareable. It includes the portable core and
reusable skills, while excluding local project registries, `.ai/` scratch state,
author-specific project packs, recovery logs, and product-specific operational
notes.

**Public repo:** `https://github.com/Daniellaguips/ai-agent-os`

If you are an AI reading this in a project, start with `AGENT-CONTRACT.md`. It is
short and binding. If you are installing the system on a new machine, start with
`SETUP.md`.

## What This Adds

- **One start command:** `bin/ai-os-status.sh` prints repo state, branch drift,
  release tags, active locks, handoff, recovery state, and dirty-path buckets.
- **Mechanical QA gate:** `bin/ai-os-gate-check.sh` verifies pre-merge QA evidence
  exists before a branch is merged into a release line — including the two
  Counterpart Rule fields, `counterpart:` and `removed:`.
- **Counterpart check:** `bin/ai-os-counterpart-check.sh` catches the two failures a
  normal stack lets through, because every gate in it is *addition-biased*: a
  function added that nothing calls, and a capability deleted while no test goes red.
  See `coding-standards.md` §The Counterpart Rule and `lessons.md` L1.
- **Local coordination:** `.ai/` files give multiple agents shared scratch memory:
  `LOCKS.md`, `HANDOFF.md`, `JOURNAL.md`, and `DIRTY.md`.
- **Atomic locks:** `bin/ai-os-lock.sh` claims work via `mkdir` (acquire/release/
  check/list/reap), so two agents can't race the same lock; it mirrors to
  `LOCKS.md` and reclaims locks whose owner died.
- **Dead-agent recovery:** `bin/ai-os-watchdog.sh` captures abandoned local work
  non-destructively into `.ai/recovery/`.
- **Reusable skills:** `skills/<name>/SKILL.md` is the canonical source linked into
  both Claude and Codex.
- **Bundled debug agents:** `agents/.claude/commands/` contains the debug and
  report-bugs command team; setup exposes it through a local `debug/` symlink.
- **Setup validation:** `bin/ai-os-validate.sh --smoke` runs a temp-HOME clean
  machine setup test.
- **Behavioral self-tests:** `bin/ai-os-selftest.sh` exercises the real decision
  logic of status / gate-check / prune / lock in throwaway repos; it runs
  as part of `bin/ai-os-validate.sh`.

## Layout

```text
~/.ai-os/
  AGENT-CONTRACT.md      always-on contract and read-order map
  README.md              human-facing overview
  SETUP.md               clone, wire tools, and onboard a repo
  MINIMUM-AI-OS.md       smallest useful subset
  workflows.md           branch, PR, release, QA, DB, and finish protocol
  coding-standards.md    default coding and regression-test standards
  agent-coordination.md  locks, handoff, dirty-state, and recovery protocol
  lessons.md             process-learning index for future agents
  agents/                bundled debug-agent command team
  skills/                portable skills plus optional project-pack layout
  bin/                   status, validation, setup, QA gate, watchdog tools
  bootstrap/             project onboarding script and `.ai/` templates
```

`debug/` is intentionally not committed. `bin/setup-clone.sh` creates it as a local
symlink to the bundled `agents/` directory, so existing hub references can use
`~/.ai-os/debug` without hardcoded machine paths.

## Skills

Portable skills live at `skills/<name>/SKILL.md` and are linked into both tools:

```bash
~/.ai-os/bin/link-skill.sh --all
```

Project-specific skills belong under `skills/project/<pack>/<skill>/SKILL.md` and
are opt-in:

```bash
~/.ai-os/bin/link-skill.sh --project <pack>
```

The public edition ships only portable root skills. Add your own project packs in
your fork or local clone when a workflow is product-specific.

## Setup

From a fresh clone:

```bash
git clone https://github.com/Daniellaguips/ai-agent-os.git ~/.ai-os
~/.ai-os/bin/setup-clone.sh
```

Then wire your tools:

- Claude Code: add `@~/.ai-os/AGENT-CONTRACT.md` to `~/.claude/CLAUDE.md`.
- Codex: point `~/.codex/AGENTS.md` at `~/.ai-os/AGENT-CONTRACT.md`.
- Project repos: run `~/.ai-os/bootstrap/init-project.sh` from the repo root.

For details and environment variables, see `SETUP.md`.

## Validate

Run the mechanical checks:

```bash
~/.ai-os/bin/ai-os-validate.sh
```

Before sharing setup, skill-layout, or bootstrap changes, run the clean-machine
smoke test:

```bash
~/.ai-os/bin/ai-os-validate.sh --smoke
```

The smoke test clones the hub into a temporary `HOME`, runs `setup-clone.sh`,
verifies bundled debug-agent symlinking, portable skill links, optional project-pack
behavior, and project bootstrap. It does not write to your real `~/.claude` or
`~/.codex` directories.

## Self-Improvement Loops

This system is meant to get stricter when it fails.

1. **Bug loop:** escaped bugs become reusable debug patterns or regression checks.
2. **Process loop:** coordination, handoff, tooling, or release-process failures
   become durable lessons, contract rules, validator checks, or skills.

Keep lessons generalized and safe to share. Put sensitive incident detail in the
project issue tracker, not in this hub.
