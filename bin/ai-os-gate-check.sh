#!/usr/bin/env bash
# ai-os-gate-check.sh — mechanical pre-merge assertion for the 3-stage QA gate.
#
# It does NOT run QA (that is judgment — see ~/.ai-os/qa-gate.md). It asserts
# the EVIDENCE a qa-gate run is required to leave, so a spoke PR cannot be
# "merge-then-swept" into the build line (lessons L5). The integrator runs this
# before every squash-merge into codex/integration / build/<N>-*; a non-zero
# exit blocks the merge.
#
# Gate record — local canonical, PR-body fallback (survives a wiped .ai/ or a
# different integrator machine):
#   .ai/qa-gate/<branch>.md         written by the qa-gate run at GO time
#   gh pr view <branch> --json body fallback if the local file is absent
#
# Record schema (one "key: value" per line; qa-gate.md §OUTPUT writes it):
#   pr:               <#|url|local-only>
#   diff_base:        <prev stage tag>            | "none — first build"
#   baseline:         pytest=<PASS|n/a> tsc=<PASS|n/a>
#   qa1:              <GO | findings, no blockers> | (must not say blocker/NO-GO)
#   qa2:              <GO | findings, no blockers>
#   qa3:              <GO>                          (post-fix; required for GO)
#   integration_flow: <path to the build's flow doc> | "n/a — docs-only"
#   regression:       no | yes — <ticket/source>
#   regression_test:  n/a | <path[:line] or path::test> — failed pre-fix
#   debug_pattern:    n/a | <path#Pattern N>
#   gate_extension:   n/a | same-pr:<path> | linear:<id> regression-watch:extend-gates | not-needed:<why>
#   decision:         GO | N/A — docs-only | NO-GO
#   signoff:          qa3-clean | founder-accepted: "<quote>"
#   rationale:        <required iff decision is N/A — docs-only>
#
# Terminal PASS states (exit 0):
#   decision: GO              + every assertion below holds
#   decision: N/A — docs-only + rationale present
# Anything else → exit 1, listing each failed assertion.
#
# Usage:  ai-os-gate-check.sh [branch]      # default: current branch

set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
  || { echo "ai-os-gate-check: not a git repo" >&2; exit 2; }
cd "$ROOT"

BR="${1:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}"
SAFE=$(printf '%s' "$BR" | tr '/ ' '__')
REC=".ai/qa-gate/${SAFE}.md"

FAIL=0
fail(){ printf '  \342\234\227 %s\n' "$*"; FAIL=1; }
ok(){   printf '  \342\234\223 %s\n' "$*"; }

echo "gate-check: branch=$BR"

# ---- locate the record: local first, then PR body via gh ----
SRC=""
if [ -f "$REC" ]; then
  SRC="$REC"; echo "  record: $REC (local)"
elif command -v gh >/dev/null 2>&1; then
  TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
  if gh pr view "$BR" --json body -q .body >"$TMP" 2>/dev/null && [ -s "$TMP" ]; then
    SRC="$TMP"; echo "  record: PR body via gh (local $REC absent)"
  fi
fi
if [ -z "$SRC" ]; then
  fail "no gate record (neither $REC nor a PR body). The qa-gate run must write it at GO."
  echo
  echo "GATE: BLOCKED — run /qa-gate (Claude) or follow ~/.ai-os/qa-gate.md (Codex) first."
  exit 1
fi

getk(){ grep -E "^${1}:" "$SRC" 2>/dev/null | head -1 | sed -E "s/^${1}:[[:space:]]*//"; }
trim(){ printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }
first_artifact_path(){
  # Evidence values may include line numbers, pytest selectors, anchors, or
  # prose after a dash. Extract the first local path-ish token and normalize it.
  local v="$1"
  v="${v#same-pr:}"
  v="${v#test:}"
  v="${v#pattern:}"
  v="${v#path:}"
  v=$(trim "$v")
  v=$(printf '%s' "$v" | sed -E 's/[[:space:]].*$//; s/#.*$//; s/::.*$//; s/:[0-9]+(:[0-9]+)?$//')
  v=$(trim "$v")
  [ -n "$v" ] || return 1
  case "$v" in
    /*) printf '%s\n' "$v" ;;
    ~/*) printf '%s\n' "$HOME/${v#~/}" ;;
    *)  printf '%s\n' "$ROOT/$v" ;;
  esac
}
artifact_exists(){
  local label="$1" value="$2" p
  if [ -z "$value" ] || printf '%s' "$value" | grep -qiE '^(n/a|none|no)([[:space:]]|$)'; then
    fail "$label: missing required artifact"
    return
  fi
  if p=$(first_artifact_path "$value") && [ -e "$p" ]; then
    ok "$label: $value"
  else
    fail "$label path not found on disk: $value"
  fi
}

DEC=$(getk decision)
case "$DEC" in
  "N/A — docs-only"|"N/A - docs-only"|"N/A docs-only")
    RAT=$(getk rationale)
    if [ -n "$RAT" ]; then
      ok "decision: N/A docs-only — $RAT"
      echo; echo "GATE: PASS (docs-only PR, 3-stage gate N/A — recorded, not skipped silently)."
      exit 0
    fi
    fail "decision is N/A docs-only but no 'rationale:' line"
    echo; echo "GATE: BLOCKED"; exit 1 ;;
  GO) ok "decision: GO" ;;
  "") fail "decision: missing (need GO or 'N/A — docs-only')" ;;
  *)  fail "decision: '$DEC' (need GO or 'N/A — docs-only'; NO-GO never merges)" ;;
esac

# ---- diff_base must resolve to a real tag (unless the first build) ----
DB=$(getk diff_base)
case "$DB" in
  "none — first build"|"none - first build") ok "diff_base: first build (no prior stage tag)" ;;
  "") fail "diff_base: missing (previous shipped stage tag, the QA-1 diff base)" ;;
  *)  if git rev-parse --verify --quiet "refs/tags/$DB" >/dev/null 2>&1; then
        ok "diff_base tag exists: $DB"
      else
        fail "diff_base '$DB' is not an existing tag — QA-1 diffed against a guess"
      fi ;;
esac

# ---- baseline green ----
BL=$(getk baseline)
if printf '%s' "$BL" | grep -qE 'pytest=(PASS|n/a)' \
   && printf '%s' "$BL" | grep -qE 'tsc=(PASS|n/a)'; then
  ok "baseline: $BL"
else
  fail "baseline not recorded green: '${BL:-<missing>}' (want pytest=PASS|n/a tsc=PASS|n/a)"
fi

# ---- QA-1 / QA-2 / QA-3 verdicts, no unresolved blockers ----
for k in qa1 qa2 qa3; do
  v=$(getk "$k")
  if [ -z "$v" ]; then
    fail "$k: missing"
  elif printf '%s' "$v" | grep -qiE 'blocker|NO-GO'; then
    fail "$k has unresolved blockers: $v"
  else
    ok "$k: $v"
  fi
done

# ---- integration-flow doc must exist on disk ----
IF=$(getk integration_flow)
case "$IF" in
  "n/a — docs-only"|"n/a - docs-only") ok "integration_flow: n/a (docs-only)" ;;
  "") fail "integration_flow: missing (path to the build's flow doc)" ;;
  *)  if [ -f "$IF" ]; then ok "integration_flow doc exists: $IF"
      else fail "integration_flow path not found on disk: $IF"; fi ;;
esac

# ---- sign-off ----
SO=$(getk signoff)
if [ -n "$SO" ]; then ok "signoff: $SO"
else fail "signoff: missing (qa3-clean | human-accepted: \"...\")"; fi

# ---- L5 regression evidence ----
# Every GO record must classify whether the PR fixes an escaped regression.
# If yes, the bug->test loop is mechanically asserted here: a pre-fix-failing
# test, a debug-pattern entry, and either a gate extension, tracker follow-up
# ticket, or explicit "not-needed" reason. This keeps L5 from being prose only.
REG=$(getk regression)
case "$(printf '%s' "$REG" | tr '[:upper:]' '[:lower:]')" in
  no|no[[:space:]]*|n/a|n/a[[:space:]]*)
    ok "regression: no" ;;
  yes|yes[[:space:]]*|regression|regression[[:space:]]*)
    ok "regression: $REG"
    RT=$(getk regression_test)
    artifact_exists "regression_test" "$RT"

    DP=$(getk debug_pattern)
    artifact_exists "debug_pattern" "$DP"
    if printf '%s' "$DP" | grep -qi 'debug-patterns\.md' \
       && printf '%s' "$DP" | grep -qiE 'pattern[-_ #]*[0-9]+'; then
      ok "debug_pattern names a numbered pattern"
    else
      fail "debug_pattern must cite debug-patterns.md and a numbered Pattern"
    fi

    GE=$(getk gate_extension)
    case "$GE" in
      same-pr:*)
        artifact_exists "gate_extension" "$GE" ;;
      tracker:*|Tracker:*)
        if printf '%s' "$GE" | grep -q 'regression-watch:extend-gates'; then
          ok "gate_extension: $GE"
        else
          fail "gate_extension tracker issue must include label regression-watch:extend-gates: $GE"
        fi ;;
      not-needed:*)
        WHY=$(printf '%s' "${GE#not-needed:}" | sed -E 's/^[[:space:]]+//')
        if [ -n "$WHY" ]; then ok "gate_extension: $GE"
        else fail "gate_extension not-needed requires a reason"; fi ;;
      "")
        fail "gate_extension: missing (same-pr:<path> | tracker:<id> regression-watch:extend-gates | not-needed:<why>)" ;;
      *)
        fail "gate_extension invalid: $GE" ;;
    esac ;;
  "")
    fail "regression: missing (record no, or yes with regression_test/debug_pattern/gate_extension)" ;;
  *)
    fail "regression value invalid: $REG (use 'no' or 'yes — <ticket/source>')" ;;
esac

echo
if [ "$FAIL" -eq 0 ]; then
  echo "GATE: PASS — evidence complete; integrator may squash-merge '$BR' into the build line,"
  echo "             then record the release marker required by workflows.md."
  exit 0
else
  echo "GATE: BLOCKED — do NOT merge. Resolve each failed check above (re-run qa-gate as needed)."
  echo "                Merge-then-sweep is the L5 incident; this check is why it can't recur."
  exit 1
fi
