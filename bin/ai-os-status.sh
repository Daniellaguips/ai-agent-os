#!/usr/bin/env bash
# ai-os-status.sh — the executable §Start check. ONE command that prints the
# exact state of a repo so an agent never acts blind. Every lesson L4/L5/L6 is
# an agent acting without knowing current state; this is the antidote. It is
# tool-agnostic (Claude/Codex/Cursor), reads only local files, no network, no
# creds. Run it FIRST, every session, before any other action — including
# skill / triage / "just a question" sessions (lessons L6).
#
# Sections:  REPO · BUILD STATE · COORDINATION · DIRTY STATE · NEXT
#
# Dirty-path buckets:
#   scratch  — .ai/ or a known-artifact glob (gitignored / expected noise)
#   OWNED    — matches an active .ai/LOCKS.md glob, or listed in .ai/DIRTY.md
#              (an agent has claimed it; it is in-flight, not ambiguous)
#   UNKNOWN  — anything else: unclaimed, not scratch. MUST get a disposition
#              before work starts or ends (lessons L4).
#
# Exit codes (so it composes into hooks / gate-check / the watchdog):
#   0  state legible and clean — safe to proceed
#   3  needs attention — UNKNOWN dirty paths, pending recovery, or no .ai/
#   2  unusable — path is not a git repo
#
# Usage:
#   ai-os-status.sh [repo-path]     # default: the current directory's repo
#   ai-os-status.sh --finish [path] # same, plus a pre-filled §Finish Report

set -uo pipefail

FINISH=0
if [ "${1:-}" = "--finish" ]; then FINISH=1; shift; fi
REPO_ARG="${1:-$PWD}"

cd "$REPO_ARG" 2>/dev/null || { echo "ai-os-status: cannot cd to $REPO_ARG" >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
  || { echo "ai-os-status: $REPO_ARG is not a git repo" >&2; exit 2; }
cd "$ROOT"

bold(){ printf '\033[1m%s\033[0m\n' "$*"; }
hr(){ printf -- '------------------------------------------------------------\n'; }
EXIT=0

# ---------- REPO ----------
bold "REPO"
BR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(detached)")
HEADSHA=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
echo "  path:     $ROOT"
echo "  branch:   $BR"
echo "  HEAD:     $HEADSHA"
if git rev-parse --verify --quiet "origin/$BR" >/dev/null 2>&1; then
  read -r AHEAD BEHIND < <(git rev-list --left-right --count "$BR...origin/$BR" 2>/dev/null || echo "0	0")
  echo "  vs origin/$BR:  ahead $AHEAD, behind $BEHIND"
else
  echo "  vs origin/$BR:  (no remote tracking branch)"
fi
# annotated worktree map — kills "which worktree is which" confusion.
# Harness-managed .claude/worktrees/agent-* are scratch; collapse to a count.
WTL=$(git worktree list 2>/dev/null || true)
TASK_WT=$(printf '%s\n' "$WTL" | grep -v '/\.claude/worktrees/agent-' || true)
HARNESS_N=$(printf '%s\n' "$WTL" | grep -c '/\.claude/worktrees/agent-' || true)
HARNESS_N=${HARNESS_N:-0}
if [ "$(printf '%s\n' "$TASK_WT" | grep -c .)" -gt 1 ]; then
  echo "  worktrees (task):"
  printf '%s\n' "$TASK_WT" | sed 's/^/    /'
  [ "${HARNESS_N:-0}" -gt 0 ] && echo "    (+ $HARNESS_N harness-managed .claude/worktrees/agent-* — scratch)"
fi
# rerere nudge — silent when on; CLAUDE.md requires it for conflict reuse
if [ "$(git config --get rerere.enabled 2>/dev/null || echo)" != "true" ]; then
  echo "  config:   git rerere is OFF — run: git config rerere.enabled true && git config rerere.autoupdate true"
fi
hr

# ---------- BUILD STATE ----------
bold "BUILD STATE"
NEWEST_TAG=$(git tag --list 'build/*-b*' --sort=-creatordate 2>/dev/null | head -1)
if [ -z "$NEWEST_TAG" ]; then
  echo "  no build cadence configured for this repo (no build/*-b<N>-* tags)"
else
  STAGE=$(printf '%s' "$NEWEST_TAG" | sed -E 's#^build/[^-]+-b[0-9]+-##')
  BNUM=$(printf '%s' "$NEWEST_TAG"  | sed -E 's#^build/[^-]+-b([0-9]+)-.*#\1#')
  TAGSHA=$(git rev-list -n1 "$NEWEST_TAG" 2>/dev/null | cut -c1-7)
  echo "  last shipped tag: $NEWEST_TAG  (@ $TAGSHA)"
  echo "  build:    b$BNUM    stage shipped: $STAGE"
  # Tag-drift check: if origin/main has substantive commits past the latest
  # tag, the tag-tracking system is stale and the next agent cannot derive
  # the current shipped stage from local state. Flag loudly so an integrator
  # notices on session start and either creates the missing tag or explains
  # why it is intentional.
  if git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    DRIFT=$(git rev-list --count "$NEWEST_TAG..origin/main" 2>/dev/null || echo 0)
    if [ "$DRIFT" -gt 0 ] 2>/dev/null && [ "$DRIFT" != "0" ]; then
      echo "  ⚠ origin/main is $DRIFT commit(s) past $NEWEST_TAG — TAG DRIFT."
      echo "    Every commit on main labeled [debug-only]/impl must have a"
      echo "    matching build tag (workflows.md §Release lifecycle, lessons L10)."
      echo "    Recent main commits past the latest tag:"
      git log --oneline "$NEWEST_TAG..origin/main" 2>/dev/null | head -5 | sed 's/^/      /'
    fi
  fi
  if git rev-parse --verify --quiet origin/codex/integration >/dev/null 2>&1; then
    UNREL=$(git rev-list --count "$NEWEST_TAG..origin/codex/integration" 2>/dev/null || echo "?")
    echo "  origin/codex/integration: $UNREL commit(s) past $NEWEST_TAG (unreleased)"
  fi
  case "$STAGE" in
    impl)
      echo "  next legal: debug-only to main for this release surface; new impl stays parked."
      echo "              Non-affected implementation may merge separately only with"
      echo "              documented release impact: none and no direct debug-main inclusion." ;;
    debug*)
      echo "  next legal: debug-only continues — another debug round, OR (only"
      echo "              after founder sign-off + tag) build $((BNUM+1)) impl opens." ;;
    *)
      echo "  next legal: unrecognized stage '$STAGE' — apply cadence rules by hand." ;;
  esac
fi
hr

# ---------- COORDINATION ----------
bold "COORDINATION"
if [ ! -d .ai ]; then
  echo "  .ai/ MISSING — run:  ~/.ai-os/bootstrap/init-project.sh"
  EXIT=3
else
  LOCK_LINES=$(grep -E '^- \[LOCKED\]' .ai/LOCKS.md 2>/dev/null || true)
  if [ -n "$LOCK_LINES" ]; then
    echo "  LOCKS (active):"
    printf '%s\n' "$LOCK_LINES" | sed 's/^/    /'
  else
    echo "  LOCKS: none active"
  fi
  if [ -f .ai/HANDOFF.md ]; then
    # Only the ACTIVE region counts: after the first '---', before the '<!--'
    # template-example comment. Without this the commented example's
    # "**Status:** in progress" line is a false "in flight" (observed bug).
    HBODY=$(awk 'inb && /<!--/{exit} /^---[[:space:]]*$/{inb=1; next} inb' .ai/HANDOFF.md)
    HS=$(printf '%s\n' "$HBODY" | grep -E '^\*\*Status:\*\*'  | head -1 || true)
    HL=$(printf '%s\n' "$HBODY" | grep -E '^\*\*Tracker:\*\*'  | head -1 || true)
    HB=$(printf '%s\n' "$HBODY" | grep -E '^\*\*Branch'       | head -1 || true)
    if [ -n "$HS" ]; then
      echo "  HANDOFF (in flight):"
      for l in "$HS" "$HB" "$HL"; do [ -n "$l" ] && printf '    %s\n' "$l"; done
    else
      echo "  HANDOFF: empty (nothing in flight)"
    fi
  fi
  if [ -f .ai/JOURNAL.md ]; then
    echo "  JOURNAL (last 3):"
    grep -E '^[0-9]{4}-[0-9]{2}' .ai/JOURNAL.md | tail -3 | sed 's/^/    /'
  fi
  if compgen -G ".ai/recovery/*/RECOVERY.md" >/dev/null 2>&1; then
    for r in .ai/recovery/*/RECOVERY.md; do
      st=$(grep -E '^linear_status:' "$r" 2>/dev/null | head -1 | awk '{print $2}')
      if [ "$st" = "pending" ]; then
        echo "  RECOVERY: PENDING — $r"
        echo "            file/update the tracker per agent-coordination §Liveness."
        EXIT=3
      fi
    done
  fi
fi
hr

# ---------- DIRTY STATE ----------
bold "DIRTY STATE"
PORC=$(git status --porcelain 2>/dev/null || true)
# LOCKS spec is "<glob/paths> — <agent> — …"; the path field is often a
# comma-separated list on ONE line. Split it to individual globs or OWNED
# never matches (the bucket that keeps an in-flight agent off exit 3).
# Split comma- or semicolon-separated path lists; never treat the whole
# field as one glob (advisor blocker: OWNED bucket must work).
LOCK_GLOBS=$(grep -E '^- \[LOCKED\]' .ai/LOCKS.md 2>/dev/null \
  | sed -E 's/^- \[LOCKED\] //; s/ — .*//' \
  | tr ',;' '\n' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
  | grep -v '^$' || true)

NOW_EPOCH=$(date +%s 2>/dev/null || echo 0)
# Stale-OWNED policy (L21): a path parked in .ai/DIRTY.md is OWNED, but OWNED is
# not a permanent parking lot. A park older than this many days is flagged and
# counts toward "needs attention" (exit 3) so it gets salvaged/shipped/discarded
# instead of trusted forever. Active LOCKS are never stale. Generous default so
# normal in-flight parks stay green; override with AI_OS_STALE_OWNED_DAYS.
STALE_OWNED_DAYS="${AI_OS_STALE_OWNED_DAYS:-14}"

path_locked(){ # $1=path -> 0 if covered by an active LOCKS glob
  local p="$1" g
  [ -n "$LOCK_GLOBS" ] || return 1
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    [ "$p" = "$g" ] && return 0
    case "$p" in "$g"/*) return 0;; esac
    # Wildcard locks only — unquoted paths with () would be case-pattern syntax.
    if [[ "$g" == *[*?]* ]]; then
      # shellcheck disable=SC2254
      case "$p" in $g) return 0;; esac
    fi
  done <<< "$LOCK_GLOBS"
  return 1
}

classify(){ # $1=path -> echoes bucket
  local p="$1"
  case "$p" in
    .ai/*) echo scratch; return;;
    *.log|*.tgz|*.tmp|*.png|*.jpg|*.jpeg|*.DS_Store|*screenshot*) echo scratch; return;;
    *.tf-feedback/*|node_modules/*|.cursor/*|.claude/worktrees/*) echo scratch; return;;
    *-local-artifacts/*) echo scratch; return;;
  esac
  if path_locked "$p"; then echo OWNED; return; fi
  if [ -f .ai/DIRTY.md ] && grep -qF -- "$p" .ai/DIRTY.md 2>/dev/null; then
    echo OWNED; return
  fi
  echo UNKNOWN
}

epoch_of(){ # $1=YYYY-MM-DD -> epoch seconds (BSD date, then GNU date)
  date -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null || echo 0
}
dirty_park_age_days(){ # $1=path -> age (days) of the NEWEST .ai/DIRTY.md mention, or empty
  [ -f .ai/DIRTY.md ] || return 0
  local ts e
  ts=$(grep -F -- "$1" .ai/DIRTY.md 2>/dev/null | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | tail -1)
  [ -z "$ts" ] && return 0
  e=$(epoch_of "$ts"); [ "${e:-0}" -gt 0 ] 2>/dev/null || return 0
  echo $(( (NOW_EPOCH - e) / 86400 ))
}

if [ -z "$PORC" ]; then
  echo "  clean — no tracked or untracked changes"
else
  UNK=0; STALEOWN=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    p="${line:3}"; p="${p##* -> }"   # drop status cols + rename "old -> new"
    b=$(classify "$p")
    note=""
    # L21 teeth: a DIRTY.md-parked OWNED path (NOT one held by an active lock)
    # that has sat past the window is flagged and gates the exit.
    if [ "$b" = "OWNED" ] && ! path_locked "$p"; then
      age=$(dirty_park_age_days "$p")
      if [ -n "$age" ] && [ "$age" -gt "$STALE_OWNED_DAYS" ] 2>/dev/null; then
        note="  ⚠ parked ${age}d in .ai/DIRTY.md — resolve per L21 (salvage/ship/lock/discard)"
        STALEOWN=$((STALEOWN+1))
      fi
    fi
    printf '  [%-7s] %s%s\n' "$b" "$p" "$note"
    [ "$b" = "UNKNOWN" ] && UNK=$((UNK+1))
  done < <(printf '%s\n' "$PORC")
  if [ "$UNK" -gt 0 ]; then
    echo
    echo "  -> $UNK path(s) UNKNOWN. Give EACH a disposition before starting or"
    echo "     ending work (lessons L4): ship via a scoped PR / claim in"
    echo "     .ai/LOCKS.md / record owner+plan in .ai/DIRTY.md / move out of the"
    echo "     repo as local scratch / discard. 'Not mine' is not a disposition."
    EXIT=3
  fi
  if [ "$STALEOWN" -gt 0 ]; then
    echo
    echo "  -> $STALEOWN OWNED path(s) parked >${STALE_OWNED_DAYS}d in .ai/DIRTY.md."
    echo "     OWNED is not a permanent parking lot (lessons L21): salvage to a clean"
    echo "     branch, ship via a scoped PR, re-lock as active work, or discard."
    echo "     (Window: AI_OS_STALE_OWNED_DAYS; active LOCKS never go stale.)"
    EXIT=3
  fi
fi
hr

# ---------- NEXT ----------
bold "NEXT"
if [ "$EXIT" -eq 0 ]; then
  echo "  State legible & clean — safe to proceed with the §Start-cleared task."
else
  echo "  NOT clear to start new work. Resolve the UNKNOWN dirt and/or pending"
  echo "  recovery above first (agent-coordination §Start / lessons L4,L6)."
fi

# ---------- optional: §Finish Report scaffold ----------
if [ "$FINISH" -eq 1 ]; then
  hr
  bold "§FINISH REPORT (fill in, then paste into the final chat response)"
  cat <<EOF
  - Pending work: <none | what + tracker id>
  - Active locks: $( [ -n "${LOCK_LINES:-}" ] && echo "YES (see COORDINATION)" || echo "none" )
  - In-flight handoff: $( [ -n "${HS:-}" ] && echo "YES — ${HL:-(no tracker line)}" || echo "none" )
  - Recovery files: $( [ "$EXIT" = 3 ] && grep -lq pending .ai/recovery/*/RECOVERY.md 2>/dev/null && echo "PENDING — file tracker issue" || echo "none" )
  - Dirty paths from THIS agent: <name each bucket + disposition, or 'none'>
  - Deliberately left to tracker/human: <list, or 'none'>
EOF
fi

exit "$EXIT"
