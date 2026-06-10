#!/usr/bin/env bash
# setup-clone.sh — make a fresh clone of ~/.ai-os usable on a new machine.
#
# The bundled debug-agent team lives in agents/ and is surfaced through the
# git-ignored `debug/` symlink. A fresh clone has no `debug/` symlink yet, and its
# portable shared skills are not wired into Claude/Codex. This script wires both
# idempotently and non-destructively. Project-pack skills are opt-in. It never edits
# your global tool config for you; it prints the one-time lines to add.
#
# Safe to re-run. Never deletes anything (backs up before relinking). Degrades
# gracefully with a clear message if the bundled agents directory is missing — your
# first contact with the OS should not be a stack trace.
#
# Usage:  ~/.ai-os/bin/setup-clone.sh
#   env:  AI_OS_AGENTS_DIR=/path/to/agents   # optional override for debug agents
set -uo pipefail

HUB="$HOME/.ai-os"
AGENTS_DIR="${AI_OS_AGENTS_DIR:-$HUB/agents}"

say(){ printf '  %s\n' "$*"; }
warn(){ printf '  ! %s\n' "$*" >&2; }

echo "ai-os: wiring this clone for use"

# --- 1) Bundled debug agents, surfaced as the debug/ symlink ------------------
if [ -d "$AGENTS_DIR/.claude/commands" ]; then
  say "debug agents present: $AGENTS_DIR"
else
  warn "debug agents not found at $AGENTS_DIR."
  warn "Use the bundled $HUB/agents directory, or set AI_OS_AGENTS_DIR to another checkout."
fi

# (re)create the debug/ symlink only if the target now exists
if [ -d "$AGENTS_DIR/.claude/commands" ]; then
  if [ -L "$HUB/debug" ] && [ "$(readlink "$HUB/debug")" = "$AGENTS_DIR" ]; then
    say "debug/ symlink ok"
  else
    if [ -e "$HUB/debug" ] && [ ! -L "$HUB/debug" ]; then
      mv "$HUB/debug" "$HUB/debug.bak-$$"
      say "backed up existing debug/ -> debug.bak-$$"
    fi
    ln -sfn "$AGENTS_DIR" "$HUB/debug"
    say "linked debug/ -> $AGENTS_DIR"
  fi
else
  warn "debug/ not linked yet (no debug-agent dir — see messages above)."
fi

# --- 2) Wire portable shared skills into Claude + Codex (idempotent) -----------
if [ -x "$HUB/bin/link-skill.sh" ]; then
  echo "  linking portable shared skills into Claude + Codex"
  "$HUB/bin/link-skill.sh" --all || warn "skill linking reported an issue (non-fatal)"
fi

# --- 3) Remind about the global wiring (we do NOT edit your globals for you) ---
cat <<EOF

ai-os: clone wired. To finish (one-time — see README "How tools pick this up"):
  - Claude Code:  add   @$HUB/AGENT-CONTRACT.md   to ~/.claude/CLAUDE.md
  - Codex:        point ~/.codex/AGENTS.md at $HUB/AGENT-CONTRACT.md
  - Onboard a repo:  cd <your-repo> && $HUB/bootstrap/init-project.sh
  - Optional project packs:  $HUB/bin/link-skill.sh --project <pack>

Health-check any repo anytime:  $HUB/bin/ai-os-status.sh <repo-path>
EOF
