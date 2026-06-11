#!/usr/bin/env bash
# ai-os-lock.sh — ATOMIC coordination locks for agents sharing one repo.
#
# Why: the markdown LOCKS.md protocol is advisory and racy. Two agents both run
# the §Start check, both see "no lock", both append — classic TOCTOU — and the
# whole-file Edit that "appends" is itself a lost update. This primitive makes
# claiming a lock atomic via mkdir() (a POSIX-atomic create-or-fail), serializes
# every LOCKS.md mirror write under a short-lived index lock, and detects locks
# whose holder process has died. It KEEPS LOCKS.md in sync so ai-os-status.sh
# OWNED matching and humans keep working — agents just stop racing.
#
# Identity (from env, with sensible defaults):
#   AI_OS_AGENT    claude | codex | cursor        (default: claude)
#   AI_OS_SESSION  opaque session id              (default: pid-based)
#   AI_OS_AGENT_PID  the agent's STABLE pid, if known. Agents invoke via short-
#                  lived shells, so this is opt-in; when set it enables
#                  process-liveness reclaim. When unset, staleness is TTL-only.
# Tunables:
#   AI_OS_LOCK_TTL          seconds before an un-refreshed lock is stale (default 7200 = 2h)
#   AI_OS_LOCK_WAIT         seconds to wait for the index lock (default 5)
#
# Commands:
#   acquire <slug> [reason]   claim <slug>; exit 0 on success, 3 if held by a live owner
#   release <slug>            release a lock you (or anyone) hold
#   check   <slug>            exit 0 free, 3 held (prints the holder)
#   list                      show active locks (+ DEAD markers for dead holders)
#   reap                      release locks whose holder process is gone / TTL-expired
#   mine                      locks held by THIS agent+session
#
# <slug> is an arbitrary name. Use a path or glob (e.g. src/api/*.ts) to also get
# ai-os-status OWNED bucketing for free; use an area name for a coarse claim.
#
# Local-only, no network, tool-agnostic. Exit: 0 ok · 3 contended/held · 2 misuse.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
  || { echo "ai-os-lock: not a git repo" >&2; exit 2; }
cd "$ROOT"

AGENT="${AI_OS_AGENT:-claude}"
SESSION="${AI_OS_SESSION:-pid-$$}"
TTL="${AI_OS_LOCK_TTL:-7200}"
WAIT="${AI_OS_LOCK_WAIT:-5}"
HOST="$(hostname 2>/dev/null || echo localhost)"
LOCKDIR=".ai/locks"
INDEX="$LOCKDIR/.index"
LOCKS_MD=".ai/LOCKS.md"
NOW=$(date +%s)
ISO=$(date -u +%Y-%m-%dT%H:%MZ)

mkdir -p "$LOCKDIR"

# ---- slug -> safe dir name (slugs may contain / and *) -------------------------
safe(){ printf '%s' "$1" | tr '/ *?:' '_____'; }

# ---- index lock: serialize all LOCKS.md mirror writes --------------------------
hold_index(){
  local waited=0
  while ! mkdir "$INDEX" 2>/dev/null; do
    # steal an index lock abandoned by a dead process (stale > 30s)
    if [ -f "$INDEX/pid" ]; then
      local ip ih im
      ip=$(cat "$INDEX/pid" 2>/dev/null || echo); ih=$(cat "$INDEX/host" 2>/dev/null || echo)
      im=$(stat -f %m "$INDEX" 2>/dev/null || stat -c %Y "$INDEX" 2>/dev/null || echo "$NOW")
      if { [ "$ih" = "$HOST" ] && [ -n "$ip" ] && ! kill -0 "$ip" 2>/dev/null; } \
         || [ $((NOW - im)) -gt 30 ]; then
        rm -rf "$INDEX" 2>/dev/null; continue
      fi
    fi
    sleep 0.1; waited=$((waited+1))
    [ "$waited" -ge $((WAIT*10)) ] && { echo "ai-os-lock: index busy ${WAIT}s" >&2; return 1; }
  done
  printf '%s' "$$"   > "$INDEX/pid"
  printf '%s' "$HOST" > "$INDEX/host"
  return 0
}
drop_index(){ rm -rf "$INDEX" 2>/dev/null || true; }

metaval(){ grep -E "^$1=" "$2" 2>/dev/null | head -1 | sed -E "s/^$1=//"; }

# ---- is a lock dir held by a DEAD owner? (same host + pid gone, or TTL passed) --
is_dead(){ # $1=lockdir
  local m="$1/meta" lh lp le
  [ -f "$m" ] || return 0
  lh=$(metaval host "$m"); lp=$(metaval pid "$m"); le=$(metaval epoch "$m")
  if [ "$lh" = "$HOST" ] && [ -n "$lp" ] && ! kill -0 "$lp" 2>/dev/null; then return 0; fi
  [ -n "$le" ] && [ $((NOW - le)) -gt "$TTL" ] && return 0
  return 1
}

# ---- rewrite the LOCKS.md mirror from the live lock dirs (call under index) -----
sync_locks_md(){
  local d header body="" m
  header="# Active locks"
  for d in "$LOCKDIR"/*/; do
    [ -d "$d" ] || continue
    m="$d/meta"; [ -f "$m" ] || continue
    body="${body}- [LOCKED] $(metaval slug "$m") — $(metaval agent "$m") — $(metaval worktree "$m") ($(metaval branch "$m")) — $(metaval iso "$m") — $(metaval reason "$m") [lock:$(metaval safe "$m")]
"
  done
  if [ -z "$body" ]; then
    printf '%s\n\nNo active locks.\n' "$header" > "$LOCKS_MD"
  else
    printf '%s\n\n%s' "$header" "$body" > "$LOCKS_MD"
  fi
}

cmd="${1:-}"; shift || true
case "$cmd" in
  acquire)
    slug="${1:-}"; reason="${2:-work in progress}"
    [ -n "$slug" ] || { echo "usage: ai-os-lock acquire <slug> [reason]" >&2; exit 2; }
    sf=$(safe "$slug"); d="$LOCKDIR/$sf"
    hold_index || exit 2
    if [ -d "$d" ]; then
      if is_dead "$d"; then
        echo "ai-os-lock: reclaiming dead lock '$slug' (held by $(metaval agent "$d/meta"), owner gone)"
        rm -rf "$d"
      else
        echo "ai-os-lock: '$slug' HELD by $(metaval agent "$d/meta") session $(metaval session "$d/meta") since $(metaval iso "$d/meta")"
        echo "            reason: $(metaval reason "$d/meta")"
        drop_index; exit 3
      fi
    fi
    mkdir -p "$d"
    {
      printf 'slug=%s\n' "$slug";   printf 'safe=%s\n' "$sf"
      printf 'agent=%s\n' "$AGENT"; printf 'session=%s\n' "$SESSION"
      printf 'pid=%s\n' "${AI_OS_AGENT_PID:-}"; printf 'host=%s\n' "$HOST"
      printf 'branch=%s\n' "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
      printf 'worktree=%s\n' "$ROOT"
      printf 'epoch=%s\n' "$NOW";   printf 'iso=%s\n' "$ISO"
      printf 'reason=%s\n' "$reason"
    } > "$d/meta"
    sync_locks_md
    drop_index
    echo "ai-os-lock: acquired '$slug' for $AGENT ($SESSION)"
    exit 0 ;;

  release)
    slug="${1:-}"; [ -n "$slug" ] || { echo "usage: ai-os-lock release <slug>" >&2; exit 2; }
    sf=$(safe "$slug"); d="$LOCKDIR/$sf"
    hold_index || exit 2
    if [ -d "$d" ]; then rm -rf "$d"; sync_locks_md; drop_index; echo "ai-os-lock: released '$slug'"; exit 0
    else sync_locks_md; drop_index; echo "ai-os-lock: '$slug' was not held"; exit 0; fi ;;

  check)
    slug="${1:-}"; [ -n "$slug" ] || { echo "usage: ai-os-lock check <slug>" >&2; exit 2; }
    d="$LOCKDIR/$(safe "$slug")"
    if [ -d "$d" ] && ! is_dead "$d"; then
      echo "HELD '$slug' by $(metaval agent "$d/meta") ($(metaval session "$d/meta")) since $(metaval iso "$d/meta")"; exit 3
    fi
    echo "FREE '$slug'"; exit 0 ;;

  list)
    found=0
    for d in "$LOCKDIR"/*/; do
      [ -d "$d" ] && [ -f "$d/meta" ] || continue
      found=1
      if is_dead "$d"; then tag="DEAD"; else tag="live"; fi
      printf '  [%s] %-28s %s (%s) — %s — %s\n' "$tag" "$(metaval slug "$d/meta")" \
        "$(metaval agent "$d/meta")" "$(metaval session "$d/meta")" \
        "$(metaval iso "$d/meta")" "$(metaval reason "$d/meta")"
    done
    [ "$found" -eq 0 ] && echo "  (no active locks)"
    exit 0 ;;

  reap)
    hold_index || exit 2
    n=0
    for d in "$LOCKDIR"/*/; do
      [ -d "$d" ] && [ -f "$d/meta" ] || continue
      if is_dead "$d"; then echo "  reaped DEAD lock '$(metaval slug "$d/meta")' ($(metaval agent "$d/meta"))"; rm -rf "$d"; n=$((n+1)); fi
    done
    sync_locks_md; drop_index
    echo "ai-os-lock: reaped $n dead lock(s)"
    exit 0 ;;

  mine)
    for d in "$LOCKDIR"/*/; do
      [ -d "$d" ] && [ -f "$d/meta" ] || continue
      [ "$(metaval agent "$d/meta")" = "$AGENT" ] && [ "$(metaval session "$d/meta")" = "$SESSION" ] \
        && printf '  %s — %s\n' "$(metaval slug "$d/meta")" "$(metaval reason "$d/meta")"
    done
    exit 0 ;;

  *) echo "usage: ai-os-lock {acquire|release|check|list|reap|mine} ..." >&2; exit 2 ;;
esac
