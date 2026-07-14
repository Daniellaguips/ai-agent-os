#!/usr/bin/env bash
# ai-os-counterpart-check.sh — mechanical check for the Counterpart Rule.
#
# The rule (coding-standards.md §The Counterpart Rule): creating an artifact is
# not the task — closing its loop is. Every artifact ships with its counterpart
# in the SAME PR: function->caller, rule->gate, queue->consumer, spec->code,
# capability->a test that goes red when it's deleted, branch->merge.
#
# Why a script and not just prose: every gate in a normal stack is
# ADDITION-BIASED. Typecheck passes when you delete a function and its only
# caller. Tests pass when nothing covered the capability. Review reads the `+`
# lines. So capability loss and never-wired code both fail OPEN. This check is
# the thing that explicitly looks at the other half of the diff.
#
# It asserts two things a normal stack does not:
#
#   1. ADDED  — a function added in this diff that nothing in the tree calls
#               is an orphan (no counterpart). Exit 1.
#   2. REMOVED— a definition deleted from source while NO test file is touched
#               is an unguarded deletion: nothing went red, so nothing noticed.
#               Exit 1 until it is acknowledged.
#
# It is deliberately conservative: it only reports named top-level definitions
# in languages it understands, and it never edits anything. A finding is a
# question you must answer ("what calls this?" / "what went red?"), not proof of
# a bug. Answer it in code, or acknowledge it explicitly — both leave a trail.
#
# Escape hatches (all explicit, all leave a trail):
#   # counterpart: <reason>     comment on/above the definition (public API,
#                               plugin entrypoint, framework-invoked hook, ...)
#   --allow-orphan <name>       repeatable, for names you cannot annotate
#   --ack-removals <reason>     acknowledge deletions reviewed with no test
#   --warn-only                 report findings but always exit 0
#
# Usage:
#   ai-os-counterpart-check.sh [--base <ref>] [--warn-only]
#                              [--allow-orphan <name>]... [--ack-removals <why>]
#
# Default base: merge-base with origin/HEAD (or main/master), else HEAD~1.
#
# Exit: 0 clean or --warn-only · 1 findings · 2 usage/environment error.

set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
  || { echo "ai-os-counterpart-check: not a git repo" >&2; exit 2; }
cd "$ROOT"

BASE=""
WARN_ONLY=0
ACK_REMOVALS=""
ALLOW_ORPHANS=" "

usage(){
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ "${1:-}" ]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 || true ;;
    --warn-only) WARN_ONLY=1; shift ;;
    --allow-orphan) ALLOW_ORPHANS="${ALLOW_ORPHANS}${2:-} "; shift 2 || true ;;
    --ack-removals) ACK_REMOVALS="${2:-}"; shift 2 || true ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ---- resolve the diff base ----------------------------------------------
if [ -z "$BASE" ]; then
  for cand in origin/HEAD origin/main origin/master main master; do
    if git rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then
      mb=$(git merge-base HEAD "$cand" 2>/dev/null) || continue
      # A base identical to HEAD tells us nothing; keep looking.
      [ -n "$mb" ] && [ "$mb" != "$(git rev-parse HEAD)" ] && { BASE="$mb"; break; }
    fi
  done
fi
if [ -z "$BASE" ]; then
  BASE=$(git rev-parse --verify --quiet HEAD~1 2>/dev/null) || BASE=""
fi
if [ -z "$BASE" ]; then
  echo "ai-os-counterpart-check: no usable diff base (single-commit repo?); pass --base <ref>" >&2
  exit 2
fi

FAIL=0
FINDINGS=0
finding(){ printf '  \342\234\227 %s\n' "$*"; FINDINGS=$((FINDINGS+1)); FAIL=1; }
ok(){       printf '  \342\234\223 %s\n' "$*"; }
note(){     printf '  \342\200\242 %s\n' "$*"; }

echo "counterpart-check: base=$(git rev-parse --short "$BASE") head=$(git rev-parse --short HEAD)"

# A test file is anything a human would call a test. Test functions are invoked
# by discovery, not by a caller, so they are exempt from the orphan check — and
# a touched test file is what satisfies the removal check.
is_test_path(){
  printf '%s' "$1" | grep -qiE '(^|/)(tests?|__tests__|spec|specs|e2e)/|(^|/)(test_[^/]+|[^/]+_test|[^/]+\.test|[^/]+\.spec)\.[a-z]+$|(^|/)conftest\.py$|selftest'
}

# Definition patterns we understand, as extended regexes over a single line.
# Conservative on purpose: named, top-level-ish definitions only. Class methods,
# anonymous functions, and dynamic dispatch are out of scope — a check nobody
# trusts is a check everybody disables.
def_names_from(){ # stdin: lines of code -> stdout: one bare name per line
  sed -E -n \
    -e 's/^[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(\)[[:space:]]*\{.*$/\2/p' \
    -e 's/^[[:space:]]*def[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(.*$/\1/p' \
    -e 's/^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*[(<].*$/\3/p' \
    -e 's/^[[:space:]]*(export[[:space:]]+)?(const|let)[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*=[[:space:]]*(async[[:space:]]*)?\(.*\)[[:space:]]*=>.*$/\3/p' \
  | sort -u
}

# Names that are invoked by a runtime/framework/shell rather than by an in-repo
# caller. Not a loophole: each is a real, well-known entrypoint convention.
is_entrypoint(){
  case "$1" in
    main|usage|setup|teardown|handler|default|init|run|cleanup|trap) return 0 ;;
  esac
  return 1
}

is_allowed_orphan(){ printf '%s' "$ALLOW_ORPHANS" | grep -qF " $1 "; }

# An explicit `# counterpart: <reason>` marker on the definition line or the
# line above it declares the loop closed outside this repo (public API, plugin
# hook). Explicit, greppable, and reviewable — unlike silence.
has_counterpart_marker(){ # file name
  local f="$1" n="$2" ln
  [ -f "$f" ] || return 1
  ln=$(grep -nE "(^|[^A-Za-z0-9_])${n}[[:space:]]*(\(|=)" "$f" 2>/dev/null | head -1 | cut -d: -f1)
  [ -n "$ln" ] || return 1
  # the definition line itself, or the line directly above it
  sed -n "$((ln > 1 ? ln - 1 : 1)),${ln}p" "$f" 2>/dev/null \
    | grep -qiE '(#|//|\*)[[:space:]]*counterpart:'
}

# Does anything other than the definition itself reference this name?
# We count references across all tracked files; the definition site contributes
# its own line, so we require a reference that is NOT a definition line.
has_caller(){ # name deffile
  local n="$1" f="$2" hits
  hits=$(git grep -I -n -w -e "$n" -- . 2>/dev/null \
    | grep -vE ":[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+${n}[[:space:]]*[(<]" \
    | grep -vE ":[[:space:]]*def[[:space:]]+${n}[[:space:]]*\(" \
    | grep -vE ":[[:space:]]*(function[[:space:]]+)?${n}[[:space:]]*\(\)[[:space:]]*\{" \
    | grep -vE ":[[:space:]]*(export[[:space:]]+)?(const|let)[[:space:]]+${n}[[:space:]]*=" \
    | grep -cE '.')
  [ "${hits:-0}" -gt 0 ]
}

# ---- collect changed files ----------------------------------------------
CHANGED=$(git diff --name-only "$BASE"...HEAD 2>/dev/null)
if [ -z "$CHANGED" ]; then
  echo "  (no changes vs base)"
  echo
  echo "COUNTERPART: PASS — nothing to check."
  exit 0
fi

TOUCHED_TEST=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if is_test_path "$f"; then TOUCHED_TEST=1; fi
done <<EOF
$CHANGED
EOF

# ============================================================
# 1. ADDED — orphan check (function with no caller)
# ============================================================
echo
echo "added — every new function needs a caller:"

ORPHANS=0
CHECKED=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue            # deleted/renamed away — handled below
  is_test_path "$f" && continue      # test fns are discovered, not called
  case "$f" in
    *.sh|*.bash|*.py|*.ts|*.tsx|*.js|*.jsx|*.mjs) ;;
    *) continue ;;
  esac

  added=$(git diff -U0 "$BASE"...HEAD -- "$f" 2>/dev/null \
    | grep -E '^\+' | grep -vE '^\+\+\+' | sed -E 's/^\+//')
  [ -n "$added" ] || continue

  names=$(printf '%s\n' "$added" | def_names_from)
  [ -n "$names" ] || continue

  while IFS= read -r n; do
    [ -n "$n" ] || continue
    CHECKED=$((CHECKED+1))
    is_entrypoint "$n"        && { note "$f: $n() — entrypoint convention, exempt"; continue; }
    is_allowed_orphan "$n"    && { note "$f: $n() — allow-listed via --allow-orphan"; continue; }
    has_counterpart_marker "$f" "$n" && { note "$f: $n() — has explicit 'counterpart:' marker"; continue; }
    if has_caller "$n" "$f"; then
      ok "$f: $n() has a caller"
    else
      finding "$f: $n() is ORPHANED — added in this diff, nothing calls it. What calls this? ('nothing' is a bug, not an answer.)"
      ORPHANS=$((ORPHANS+1))
    fi
  done <<EOF
$names
EOF
done <<EOF
$CHANGED
EOF
[ "$CHECKED" -eq 0 ] && note "no new named definitions in this diff"

# ============================================================
# 2. REMOVED — capability-loss check (deletion nothing went red for)
# ============================================================
echo
echo "removed — every deleted capability needs something that went red:"

REMOVED_LIST=""
REMOVED_N=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  is_test_path "$f" && continue
  case "$f" in
    *.sh|*.bash|*.py|*.ts|*.tsx|*.js|*.jsx|*.mjs) ;;
    *) continue ;;
  esac

  deleted=$(git diff -U0 "$BASE"...HEAD -- "$f" 2>/dev/null \
    | grep -E '^-' | grep -vE '^---' | sed -E 's/^-//')
  [ -n "$deleted" ] || continue

  dnames=$(printf '%s\n' "$deleted" | def_names_from)
  [ -n "$dnames" ] || continue

  # A definition that still exists in the file was moved/rewritten, not removed.
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    if [ -f "$f" ] && printf '%s\n' "$n" | grep -q . \
       && git grep -I -q -w -e "$n" -- "$f" 2>/dev/null; then
      continue
    fi
    REMOVED_LIST="${REMOVED_LIST}${f}: ${n}()
"
    REMOVED_N=$((REMOVED_N+1))
  done <<EOF
$dnames
EOF
done <<EOF
$CHANGED
EOF

if [ "$REMOVED_N" -eq 0 ]; then
  ok "no named definitions removed"
else
  printf '%s' "$REMOVED_LIST" | while IFS= read -r line; do
    [ -n "$line" ] && note "deleted: $line"
  done
  if [ "$TOUCHED_TEST" -eq 1 ]; then
    ok "$REMOVED_N definition(s) removed, and this diff touches a test file"
  elif [ -n "$ACK_REMOVALS" ]; then
    ok "$REMOVED_N definition(s) removed — acknowledged: $ACK_REMOVALS"
  else
    finding "$REMOVED_N definition(s) removed and NO test file is touched by this diff."
    printf '      Nothing went red, so nothing would have noticed. Enumerate what you\n'
    printf '      DELETED, not just what you added. Then either add/adjust the test that\n'
    printf '      covers the remaining behavior, or re-run with:\n'
    printf '        --ack-removals "<why this loses no capability>"\n'
  fi
fi

# ============================================================
echo
if [ "$FAIL" -eq 0 ]; then
  echo "COUNTERPART: PASS — every artifact in this diff has its counterpart."
  exit 0
fi
echo "COUNTERPART: $FINDINGS finding(s) — half a loop is not a deliverable."
echo "             Close the loop, or acknowledge it explicitly. See"
echo "             coding-standards.md §The Counterpart Rule and lessons.md L1."
if [ "$WARN_ONLY" -eq 1 ]; then
  echo "             (--warn-only: not failing the build)"
  exit 0
fi
exit 1
