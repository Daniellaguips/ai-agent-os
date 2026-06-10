#!/usr/bin/env bash
# setup-clone.sh — make a fresh clone of ~/.ai-os usable on a new machine.
#
# A clone does NOT contain the debug team: it lives in a separate public repo
# (github.com/Daniellaguips/agents) and is surfaced here only as the git-ignored
# `debug/` symlink, so a fresh clone has no `debug/` at all. A clone's portable
# shared skills are also not yet wired into Claude/Codex. This script wires both
# idempotently and non-destructively. Project-pack skills are opt-in. It never
# edits your global tool config for you; it prints the one-time lines to add.
#
# Safe to re-run. Never deletes anything (backs up before relinking). Degrades
# gracefully with a clear message if git is missing or the debug repo can't be
# fetched — your first contact with the OS should not be a stack trace.
#
# Usage:  ~/.ai-os/bin/setup-clone.sh
#   env:  AI_OS_AGENTS_DIR=/path/to/agents   # if you cloned the debug team elsewhere
set -uo pipefail

HUB="$HOME/.ai-os"
AGENTS_DIR="${AI_OS_AGENTS_DIR:-$HOME/agents}"
AGENTS_REMOTE="${AI_OS_AGENTS_REMOTE:-https://github.com/Daniellaguips/agents.git}"

say(){ printf '  %s\n' "$*"; }
warn(){ printf '  ! %s\n' "$*" >&2; }

echo "ai-os: wiring this clone for use"

# --- 1) Debug team -> ~/agents, surfaced as the debug/ symlink ----------------
if [ -d "$AGENTS_DIR/.git" ]; then
  say "debug team present: $AGENTS_DIR"
elif command -v git >/dev/null 2>&1; then
  echo "  cloning debug team (public) -> $AGENTS_DIR"
  if git clone --depth 1 "$AGENTS_REMOTE" "$AGENTS_DIR"; then
    say "cloned $AGENTS_REMOTE"
  else
    warn "could not clone $AGENTS_REMOTE (offline, or git auth/network issue)."
    warn "Clone it manually to $AGENTS_DIR (or set AI_OS_AGENTS_DIR) and re-run."
  fi
else
  warn "git not found — install git, clone $AGENTS_REMOTE to $AGENTS_DIR, re-run."
fi

# (re)create the debug/ symlink only if the target now exists
if [ -d "$AGENTS_DIR" ]; then
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
  warn "debug/ not linked yet (no debug team dir — see messages above)."
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
