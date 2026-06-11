#!/usr/bin/env bash
# ai-os-guard.sh — PreToolUse hook: surface (and optionally block) an edit to a
# file another agent holds an active lock on. Advisory locks only warn if someone
# reads LOCKS.md; this gives the warning teeth at the exact moment of the edit.
#
# FAIL-OPEN by design: by default it NEVER blocks — it prints a warning and exits
# 0 so it can't wedge a workflow. Set AI_OS_ENFORCE_LOCKS=1 to hard-block a
# cross-agent edit (exit 2, which Claude Code treats as "deny + tell the model").
#
# Cheap on the hot path: with no active locks it exits in microseconds (one file
# test), so wiring it globally costs ~nothing in single-agent repos. No jq dep.
#
# Wire (PreToolUse, matcher "Edit|Write|MultiEdit"):
#   "command": "~/.ai-os/bin/ai-os-guard.sh"
# Reads hook JSON on stdin: {tool_input.file_path, session_id, cwd}.
set -uo pipefail

ENFORCE="${AI_OS_ENFORCE_LOCKS:-0}"
input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

# minimal, dependency-free JSON field extraction
jget(){ printf '%s' "$input" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
FP="$(jget file_path)"; SID="$(jget session_id)"; CWD="$(jget cwd)"
[ -n "$FP" ] || exit 0

[ -n "$CWD" ] && cd "$CWD" 2>/dev/null || exit 0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$ROOT" || exit 0
# hot-path bail: nothing to enforce (before any costly normalization)
[ -d .ai/locks ] || [ -s .ai/LOCKS.md ] || exit 0

# Past the bail (locks exist), re-extract precisely with jq if available: the
# fast sed grab above can be fooled when tool_input.content/new_string embeds
# literal "file_path":"…" text. Matters most under AI_OS_ENFORCE_LOCKS=1.
if command -v jq >/dev/null 2>&1; then
  _fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  _sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
  [ -n "$_fp" ] && FP="$_fp"
  [ -n "$_sid" ] && SID="$_sid"
fi

# repo-relative target path. Canonicalize both sides so a /var ↔ /private/var
# symlink (macOS) or a not-yet-created Write target still strips correctly.
# realpath resolves the existing prefix and keeps a non-existent leaf.
canon(){ python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || printf '%s' "$1"; }
ROOTC="$(canon "$ROOT")"
REL="$(canon "$FP")"; REL="${REL#$ROOTC/}"

matches(){ # $1=glob/slug $2=path -> 0 if the lock covers the path
  local g="$1" p="$2"
  [ "$g" = "$p" ] && return 0
  case "$p" in "$g"/*) return 0;; esac
  if [[ "$g" == *[*?]* ]]; then
    # shellcheck disable=SC2254
    case "$p" in $g) return 0;; esac
  fi
  return 1
}

CONFLICT=""; OWNER=""
# structured locks (ai-os-lock.sh) carry a session — skip my own
if [ -d .ai/locks ]; then
  for d in .ai/locks/*/; do
    [ -d "$d" ] && [ -f "$d/meta" ] || continue
    slug=$(sed -n 's/^slug=//p' "$d/meta" | head -1)
    lsid=$(sed -n 's/^session=//p' "$d/meta" | head -1)
    [ -n "$slug" ] || continue
    if matches "$slug" "$REL"; then
      [ -n "$SID" ] && [ "$lsid" = "$SID" ] && continue   # my own lock
      CONFLICT="$slug"; OWNER="$(sed -n 's/^agent=//p' "$d/meta" | head -1) ($lsid) — $(sed -n 's/^reason=//p' "$d/meta" | head -1)"
      break
    fi
  done
fi
# manual LOCKS.md globs (no session info — can't prove it's mine, so only warn).
# Skip any glob that is just the mirror of a structured lock already judged above.
if [ -z "$CONFLICT" ] && [ -f .ai/LOCKS.md ]; then
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    [ -d ".ai/locks/$(printf '%s' "$g" | tr '/ *?:' '_____')" ] && continue
    if matches "$g" "$REL"; then CONFLICT="$g"; OWNER="see .ai/LOCKS.md"; break; fi
  done < <(grep -E '^- \[LOCKED\]' .ai/LOCKS.md 2>/dev/null \
            | sed -E 's/^- \[LOCKED\] //; s/ — .*//' | tr ',;' '\n' \
            | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -v '^$')
fi

[ -n "$CONFLICT" ] || exit 0

MSG="ai-os-guard: '$REL' is under an active lock ($CONFLICT) held by $OWNER. Coordinate via .ai/ or pick other work before editing (agent-coordination §Lock)."
if [ "$ENFORCE" = "1" ]; then
  echo "$MSG Blocked (AI_OS_ENFORCE_LOCKS=1)." >&2
  exit 2                       # Claude Code: deny the tool call, feed reason to the model
fi
echo "⚠ $MSG" >&2              # fail-open: warn but allow
exit 0
