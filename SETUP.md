# Setup

This is a portable AI operating system for coding agents. It is not just a prompt
folder: the rules are backed by executable checks for repo state, merge evidence,
dead-agent recovery, skill linking, and clean-machine setup.

If you only read one file as an agent, read `AGENT-CONTRACT.md`. If you are
evaluating the smallest useful subset, read `MINIMUM-AI-OS.md`.

## Repos

| Repo | Visibility | Role |
|---|---|---|
| `github.com/Daniellaguips/ai-os-public` | public | this hub: contract, workflows, standards, coordination, lessons, tools, and portable skills |
| `github.com/Daniellaguips/agents` | public | optional debug-agent team, surfaced as a local `debug/` symlink by setup |

A fresh clone has no committed `debug/` directory and no linked tool skills yet.
`setup-clone.sh` wires those pieces idempotently.

## 1. Clone

```bash
git clone https://github.com/Daniellaguips/ai-os-public.git ~/.ai-os
```

## 2. Wire The Clone

```bash
~/.ai-os/bin/setup-clone.sh
```

The setup script:

- clones or reuses the public debug-agent repo at `~/agents`,
- creates `~/.ai-os/debug -> ~/agents`,
- links portable skills into `~/.claude/skills/` and `~/.codex/skills/`,
- prints the global tool wiring to add manually.

If your debug-agent checkout lives elsewhere:

```bash
AI_OS_AGENTS_DIR=/path/to/agents ~/.ai-os/bin/setup-clone.sh
```

## 3. Wire Your Tools

Claude Code:

```text
@/Users/<you>/.ai-os/AGENT-CONTRACT.md
```

Add that line to `~/.claude/CLAUDE.md`.

Codex:

```text
Before any action, read and follow ~/.ai-os/AGENT-CONTRACT.md.
```

Add an equivalent pointer to `~/.codex/AGENTS.md`, with the key non-negotiables
inlined if your tooling benefits from a failsafe.

Cursor and other tools can use the per-project pointer stamped by
`bootstrap/init-project.sh` when `AI_OS_STAMP_TRACKED=1`.

## 4. Onboard A Project

From any repo root:

```bash
~/.ai-os/bootstrap/init-project.sh
```

This creates local `.ai/` scratch files, adds `.ai/` to the repo's local git
exclude, enables `git rerere`, and registers the repo with the watchdog.

To stamp tracked project pointers too:

```bash
AI_OS_STAMP_TRACKED=1 ~/.ai-os/bootstrap/init-project.sh
```

Review and commit those tracked pointer changes intentionally.

## Daily Commands

Start every agent session:

```bash
~/.ai-os/bin/ai-os-status.sh
```

Check pre-merge QA evidence:

```bash
~/.ai-os/bin/ai-os-gate-check.sh <branch>
```

Before claiming a clean finish:

```bash
~/.ai-os/bin/ai-os-status.sh --finish
~/.ai-os/bin/ai-os-prune.sh
```

## Project Packs

Portable skills are linked by default:

```bash
~/.ai-os/bin/link-skill.sh --all
```

Product-specific workflows should live in opt-in project packs:

```text
skills/project/<pack>/<skill>/SKILL.md
```

Link one pack explicitly:

```bash
~/.ai-os/bin/link-skill.sh --project <pack>
```

The public edition ships without author-specific project packs.

## Verify

Run the mechanical validator:

```bash
~/.ai-os/bin/ai-os-validate.sh
```

Run the true clean-machine smoke:

```bash
~/.ai-os/bin/ai-os-validate.sh --smoke
```

To run only the smoke directly:

```bash
~/.ai-os/bin/ai-os-smoke-setup.sh
```

The smoke creates a temporary `HOME`, clones the hub into `HOME/.ai-os`, runs
`setup-clone.sh`, verifies debug-agent symlinking, portable skills, optional
project-pack behavior, and sample repo bootstrap. It does not write to your real
tool directories.

## What To Customize

The portable core is meant to be reused as-is:

```text
AGENT-CONTRACT.md
agent-coordination.md
workflows.md
coding-standards.md
qa-gate.md
lessons.md
bin/
bootstrap/
skills/
```

Customize project-specific release tags, branch naming, deployment markers, issue
tracker names, and skill packs in your project docs or a project pack. Keep customer
facts, credentials, raw recovery logs, and local machine paths out of the public hub.
