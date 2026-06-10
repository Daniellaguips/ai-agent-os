#!/usr/bin/env bash
# init-project.sh — wire a repo into ~/.ai-os without surprise tracked dirt.
# Default behavior is local-only: create .ai/ scratch, add .ai/ to the local git
# exclude file, and register the repo with the watchdog. Set
# AI_OS_STAMP_TRACKED=1 to also stamp tracked pointer docs / .gitignore.
# Existing .ai/ scratch files are never overwritten.
#
# Usage:  cd <repo> && ~/.ai-os/bootstrap/init-project.sh
#    or:  ~/.ai-os/bootstrap/init-project.sh /path/to/repo
set -euo pipefail

HUB="$HOME/.ai-os"
TPL="$HUB/bootstrap/templates"
TARGET="${1:-$PWD}"
BLOCK_FILE="$TPL/project-pointer.md"
BEGIN='<!-- BEGIN ai-os'
END='<!-- END ai-os -->'
STAMP_TRACKED="${AI_OS_STAMP_TRACKED:-0}"

cd "$TARGET"
echo "ai-os: bootstrapping $TARGET"

# --- stamp the managed pointer block into a markdown file ---------------------
# If the BEGIN/END block exists, replace it; else append. Never touches other content.
stamp_block() {
  local file="$1" header="${2:-}"
  if [[ ! -e "$file" ]]; then
    mkdir -p "$(dirname "$file")"
    { [[ -n "$header" ]] && printf '%s\n' "$header"; cat "$BLOCK_FILE"; } > "$file"
    echo "  created  $file"
    return
  fi
  if grep -qF "$BEGIN" "$file"; then
    awk -v b="$BEGIN" -v e="$END" -v bf="$BLOCK_FILE" '
      $0 ~ b {inblock=1; while ((getline line < bf) > 0) print line; close(bf); next}
      inblock && index($0, e) {inblock=0; next}
      !inblock {print}
    ' "$file" > "$file.aiotmp" && mv "$file.aiotmp" "$file"
    echo "  updated  $file (managed block refreshed)"
  else
    { printf '\n'; cat "$BLOCK_FILE"; } >> "$file"
    echo "  appended $file (managed block added; existing content untouched)"
  fi
}

if [[ "$STAMP_TRACKED" == "1" ]]; then
  stamp_block "CLAUDE.md"
  stamp_block "AGENTS.md"
  stamp_block ".cursor/rules/ai-os.mdc" $'---\ndescription: AI Operating System — read ~/.ai-os/AGENT-CONTRACT.md\nalwaysApply: true\n---'
else
  echo "  skipped  tracked pointer docs (set AI_OS_STAMP_TRACKED=1 to stamp them)"
fi

# --- .ai/ scratch dir (gitignored; never overwrite live notes) ----------------
mkdir -p .ai .ai/recovery .ai/qa-gate
for f in JOURNAL.md LOCKS.md HANDOFF.md DIRTY.md; do
  if [[ -e ".ai/$f" ]]; then
    echo "  kept     .ai/$f (already present — not overwritten)"
  else
    cp "$TPL/$f" ".ai/$f"
    echo "  created  .ai/$f"
  fi
done
# qa-gate evidence records (ai-os-gate-check.sh reads .ai/qa-gate/<branch>.md)
[[ -e .ai/qa-gate/.keep ]] || { : > .ai/qa-gate/.keep; echo "  created  .ai/qa-gate/ (pre-merge gate records)"; }

# --- enable git rerere so conflict resolutions are reused (CLAUDE.md rule) -----
if git rev-parse --git-dir >/dev/null 2>&1; then
  if [[ "$(git config --get rerere.enabled || echo)" == "true" ]]; then
    echo "  ok       git rerere already enabled"
  else
    git config rerere.enabled true
    git config rerere.autoupdate true
    echo "  updated  git rerere enabled (local repo config)"
  fi
fi

# --- ignore .ai/ (scratch is local; durable handoffs go to a tracker) ---------
if git rev-parse --git-dir >/dev/null 2>&1; then
  if [[ "$STAMP_TRACKED" == "1" ]]; then
    touch .gitignore
    if grep -qxE '\.ai/?' .gitignore; then
      echo "  ok       .gitignore already ignores .ai/"
    else
      printf '\n# AI agent local scratch (durable handoffs go to a tracker)\n.ai/\n' >> .gitignore
      echo "  updated  .gitignore (added .ai/)"
    fi
  else
    GIT_DIR="$(git rev-parse --git-dir)"
    EXCLUDE_FILE="$GIT_DIR/info/exclude"
    mkdir -p "$(dirname "$EXCLUDE_FILE")"
    touch "$EXCLUDE_FILE"
    if grep -qxE '\.ai/?' "$EXCLUDE_FILE"; then
      echo "  ok       local git exclude already ignores .ai/"
    else
      printf '\n# AI agent local scratch (durable handoffs go to a tracker)\n.ai/\n' >> "$EXCLUDE_FILE"
      echo "  updated  local git exclude (added .ai/)"
    fi
  fi
else
  echo "  note     not a git repo — skipped git ignore (.ai/ created anyway)"
fi

# --- register with the hourly watchdog (idempotent; absolute path) ------------
REG="$HOME/.ai-os/projects.txt"
ABS="$(cd "$TARGET" && pwd -P)"
touch "$REG"
if grep -qxF "$ABS" "$REG"; then
  echo "  ok       already registered with watchdog"
else
  echo "$ABS" >> "$REG"
  echo "  updated  registered $ABS with the hourly watchdog"
fi

echo "ai-os: done. This repo is now swept hourly by the dead-agent watchdog."
if [[ "$STAMP_TRACKED" == "1" ]]; then
  echo "       Tracked pointer docs were stamped; review and commit them intentionally."
else
  echo "       Tracked files were not modified; rely on global agent config or rerun with AI_OS_STAMP_TRACKED=1."
fi
