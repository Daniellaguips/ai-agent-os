#!/usr/bin/env bash
# ai-os-selftest.sh — BEHAVIORAL regression tests for the core coordination
# scripts (ai-os-status, ai-os-gate-check, ai-os-prune).
#
# ai-os-validate.sh checks shell SYNTAX, skill layout, links, and docs. It does
# NOT exercise the actual decision logic of the three scripts every session and
# every merge depends on. PR #1's gate record says those scripts were
# "behavior-tested in-session" — by hand, once, never codified. This file is
# that test, made repeatable: it spins up throwaway git repos with crafted
# .ai/ state and asserts exit codes + output, so a future edit that breaks
# OWNED bucketing, the QA-gate evidence checks, or stale-worktree detection
# fails CI instead of silently shipping.
#
# Pure local: temp repos under $TMPDIR, no network, no creds, self-cleaning.
# Run directly, or via ai-os-validate.sh which calls it.
#
# Exit: 0 all behavioral assertions hold · 1 one or more failed.
set -uo pipefail

HUB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATUS="$HUB/bin/ai-os-status.sh"
GATE="$HUB/bin/ai-os-gate-check.sh"
PRUNE="$HUB/bin/ai-os-prune.sh"
LOCK="$HUB/bin/ai-os-lock.sh"
GUARD="$HUB/bin/ai-os-guard.sh"

PASS=0; FAIL=0
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-os-selftest.XXXXXX")"
OUT="$TMP_ROOT/out"
cleanup(){ [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ] && rm -rf "$TMP_ROOT"; }
trap cleanup EXIT

pass(){ PASS=$((PASS+1)); printf '  [ok]   %s\n' "$*"; }
fail(){ FAIL=$((FAIL+1)); printf '  [FAIL] %s\n' "$*" >&2; }

# run a script, capture rc + stdout/stderr into $OUT
run(){ "$@" >"$OUT" 2>&1; RC=$?; return 0; }
expect_rc(){ # want name
  if [ "$RC" -eq "$1" ]; then pass "$2 (rc=$RC)"; else fail "$2 (rc=$RC, want $1)"; sed 's/^/        | /' "$OUT" >&2; fi
}
expect_out(){ # pattern name
  if grep -qE "$1" "$OUT"; then pass "$2"; else fail "$2 — missing /$1/"; sed 's/^/        | /' "$OUT" >&2; fi
}
expect_no_out(){ # pattern name
  if grep -qE "$1" "$OUT"; then fail "$2 — unexpected /$1/"; sed 's/^/        | /' "$OUT" >&2; else pass "$2"; fi
}

# ---- repo helpers ----
git_q(){ git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }
mkrepo(){ # -> echoes path; main branch, one commit, .ai/ hidden like a real repo
  local d="$TMP_ROOT/repo.$RANDOM$RANDOM"
  mkdir -p "$d"
  git -C "$d" init -q -b main 2>/dev/null || git -C "$d" init -q
  git -C "$d" symbolic-ref HEAD refs/heads/main 2>/dev/null || true
  printf 'seed\n' > "$d/README"
  git_q "$d" add -A; git_q "$d" commit -qm seed
  mkdir -p "$d/.ai"
  printf '# Active locks\n\nNo active locks.\n' > "$d/.ai/LOCKS.md"
  printf '.ai/\n' >> "$d/.git/info/exclude"   # real repos exclude .ai/
  printf '%s' "$d"
}

bold(){ printf '\n\033[1m# %s\033[0m\n' "$*"; }

# ============================================================
bold "ai-os-status — dirty-path bucketing & exit codes"
# ============================================================

# clean
R=$(mkrepo)
run "$STATUS" "$R"
expect_rc 0 "clean repo → exit 0"
expect_out 'clean — no tracked or untracked changes' "clean repo prints clean"

# missing .ai/
R=$(mkrepo); rm -rf "$R/.ai"
run "$STATUS" "$R"
expect_rc 3 "missing .ai/ → exit 3"
expect_out '\.ai/ MISSING' "missing .ai/ flagged"

# UNKNOWN dirty path
R=$(mkrepo); printf 'x\n' > "$R/orphan.py"
run "$STATUS" "$R"
expect_rc 3 "unclaimed dirty file → exit 3"
expect_out '\[UNKNOWN.*orphan\.py' "orphan.py bucketed UNKNOWN"

# scratch dirty path (known-artifact glob) does NOT trip exit 3
R=$(mkrepo); printf 'log\n' > "$R/debug.log"
run "$STATUS" "$R"
expect_rc 0 "scratch artifact (*.log) → exit 0"
expect_out '\[scratch.*debug\.log' "debug.log bucketed scratch"

# OWNED via single exact-path lock (modify an already-tracked file so porcelain
# reports the file, not a collapsed new directory)
R=$(mkrepo)
printf -- '- [LOCKED] README — codex — wt — 2026-06-10T00:00Z — editing\n' >> "$R/.ai/LOCKS.md"
printf 'edit\n' >> "$R/README"
run "$STATUS" "$R"
expect_rc 0 "locked file → OWNED → exit 0"
expect_out '\[OWNED.*README' "locked file bucketed OWNED"

# OWNED via COMMA-SEPARATED lock list  (regression for Cursor 2d54718)
R=$(mkrepo)
printf -- '- [LOCKED] a.py, b.py — codex — wt — 2026-06-10T00:00Z — two files one line\n' >> "$R/.ai/LOCKS.md"
printf 'a\n' > "$R/a.py"; printf 'b\n' > "$R/b.py"
run "$STATUS" "$R"
expect_rc 0 "comma-split lock list → both OWNED → exit 0"
expect_out '\[OWNED.*a\.py' "comma-split: a.py OWNED"
expect_out '\[OWNED.*b\.py' "comma-split: b.py OWNED"

# OWNED via glob lock (src/ already tracked, so a new src/*.ts shows per-file)
R=$(mkrepo)
mkdir -p "$R/src"; printf 'seed\n' > "$R/src/seed.ts"
git_q "$R" add -A; git_q "$R" commit -qm "track src"
printf -- '- [LOCKED] src/*.ts — claude — wt — 2026-06-10T00:00Z — glob lock\n' >> "$R/.ai/LOCKS.md"
printf 'z\n' > "$R/src/x.ts"
run "$STATUS" "$R"
expect_rc 0 "glob lock → OWNED → exit 0"
expect_out '\[OWNED.*src/x\.ts' "glob lock matches OWNED"

# OWNED via DIRTY.md, FRESH park → OWNED, exit 0 (not stale)
R=$(mkrepo); TODAY=$(date -u +%Y-%m-%d)
printf '%sT00:00Z codex — parked: keep.txt pending salvage\n' "$TODAY" > "$R/.ai/DIRTY.md"
printf 'k\n' > "$R/keep.txt"
run "$STATUS" "$R"
expect_rc 0 "fresh DIRTY.md park → OWNED → exit 0"
expect_out '\[OWNED.*keep\.txt' "fresh park bucketed OWNED"
expect_no_out 'parked [0-9]+d in' "fresh park not flagged stale"

# OWNED via DIRTY.md, STALE park (>14d) → exit 3  (L21 teeth)
R=$(mkrepo)
printf '2025-01-01T00:00Z codex — parked: rot.txt forgotten\n' > "$R/.ai/DIRTY.md"
printf 'r\n' > "$R/rot.txt"
run "$STATUS" "$R"
expect_rc 3 "stale DIRTY.md park (>14d) → exit 3"
expect_out 'parked [0-9]+d in \.ai/DIRTY\.md' "stale park flagged with age"
expect_out 'L21' "stale park cites L21"

# active LOCK on a path also in an OLD DIRTY.md → OWNED, NOT stale (lock wins)
R=$(mkrepo)
printf -- '- [LOCKED] both.txt — claude — wt — 2026-06-10T00:00Z — active\n' >> "$R/.ai/LOCKS.md"
printf '2025-01-01T00:00Z codex — parked: both.txt\n' > "$R/.ai/DIRTY.md"
printf 'x\n' > "$R/both.txt"
run "$STATUS" "$R"
expect_rc 0 "active lock overrides stale park → exit 0"
expect_no_out 'parked [0-9]+d' "locked path never flagged stale"

# pending recovery → exit 3
R=$(mkrepo)
mkdir -p "$R/.ai/recovery/20260101T000000"
printf 'linear_status: pending\n' > "$R/.ai/recovery/20260101T000000/RECOVERY.md"
run "$STATUS" "$R"
expect_rc 3 "pending recovery → exit 3"
expect_out 'RECOVERY: PENDING' "pending recovery surfaced"

# HANDOFF active-region parse: commented template example is NOT in-flight
R=$(mkrepo)
cat > "$R/.ai/HANDOFF.md" <<'EOF'
# Handoff — sample
Empty when nothing is in flight.
---
<!-- template example — DO NOT let this read as in-flight:
**Status:** in progress
**Branch:** example/x
-->
EOF
run "$STATUS" "$R"
expect_out 'HANDOFF: empty' "commented HANDOFF example → empty (not in-flight)"
expect_no_out 'HANDOFF \(in flight\)' "commented HANDOFF example does NOT show in-flight"

# HANDOFF with a real active-region status IS in-flight
R=$(mkrepo)
cat > "$R/.ai/HANDOFF.md" <<'EOF'
# Handoff — sample
---
**Status:** in progress
**Branch:** feature/live
**Tracker:** PROJ-123
<!-- template example below -->
EOF
run "$STATUS" "$R"
expect_out 'HANDOFF \(in flight\)' "real active HANDOFF → in-flight"

# ============================================================
bold "ai-os-gate-check — QA evidence assertions"
# ============================================================

# Writes a gate record for branch $2 in repo $1, then runs gate-check on it.
gate(){ # repo branch <<heredoc-body
  local repo="$1" br="$2" safe
  safe=$(printf '%s' "$br" | tr '/ ' '__')
  mkdir -p "$repo/.ai/qa-gate"
  cat > "$repo/.ai/qa-gate/${safe}.md"
  ( cd "$repo" && "$GATE" "$br" ) >"$OUT" 2>&1; RC=$?
}

# no record at all → BLOCKED
R=$(mkrepo)
( cd "$R" && "$GATE" nope ) >"$OUT" 2>&1; RC=$?
expect_rc 1 "missing gate record → BLOCKED"
expect_out 'no gate record' "missing record reason printed"

# minimal valid GO → PASS
R=$(mkrepo)
gate "$R" t-go <<'EOF'
pr: local-only
diff_base: none — first build
baseline: pytest=n/a tsc=n/a
qa1: GO — clean
qa2: GO — clean
qa3: GO
integration_flow: n/a — docs-only
regression: no
decision: GO
signoff: qa3-clean
EOF
expect_rc 0 "complete GO record → PASS"
expect_out 'GATE: PASS' "GO record passes"

# REGRESSION: documented happy-path value "no blockers" must NOT false-block.
# Pre-fix this FAILS (the grep 'blocker' substring collision) — that failure is
# the L5 regression evidence; the gate-check fix flips it green.
R=$(mkrepo)
gate "$R" t-noblockers <<'EOF'
pr: local-only
diff_base: none — first build
baseline: pytest=n/a tsc=n/a
qa1: GO — 2 findings, no blockers
qa2: GO — reviewed, no blockers
qa3: GO
integration_flow: n/a — docs-only
regression: no
decision: GO
signoff: qa3-clean
EOF
expect_rc 0 "GO with 'no blockers' phrasing → PASS (no substring false-block)"

# A REAL blocker must still block (fix must not over-correct)
R=$(mkrepo)
gate "$R" t-realblock <<'EOF'
pr: local-only
diff_base: none — first build
baseline: pytest=n/a tsc=n/a
qa1: GO — clean
qa2: NO-GO — blocker: auth missing on mutating endpoint
qa3: GO
integration_flow: n/a — docs-only
regression: no
decision: GO
signoff: qa3-clean
EOF
expect_rc 1 "real unresolved blocker → BLOCKED"

# decision NO-GO → BLOCKED
R=$(mkrepo)
gate "$R" t-nogo <<'EOF'
diff_base: none — first build
baseline: pytest=n/a tsc=n/a
qa1: GO
qa2: GO
qa3: GO
regression: no
decision: NO-GO
signoff: qa3-clean
EOF
expect_rc 1 "decision NO-GO → BLOCKED"

# docs-only with rationale → PASS
R=$(mkrepo)
gate "$R" t-docs <<'EOF'
decision: N/A — docs-only
rationale: pure documentation, no code/build/regression surface
EOF
expect_rc 0 "docs-only + rationale → PASS"
expect_out 'GATE: PASS' "docs-only passes"

# docs-only WITHOUT rationale → BLOCKED
R=$(mkrepo)
gate "$R" t-docs2 <<'EOF'
decision: N/A — docs-only
EOF
expect_rc 1 "docs-only without rationale → BLOCKED"

# diff_base that is not a real tag → BLOCKED
R=$(mkrepo)
gate "$R" t-badbase <<'EOF'
pr: local-only
diff_base: build/ios-b99-impl
baseline: pytest=n/a tsc=n/a
qa1: GO
qa2: GO
qa3: GO
integration_flow: n/a — docs-only
regression: no
decision: GO
signoff: qa3-clean
EOF
expect_rc 1 "diff_base not an existing tag → BLOCKED"

# regression: yes with COMPLETE L5 evidence → PASS
R=$(mkrepo)
mkdir -p "$R/tests" "$R/.claude"
printf 'def test_regress(): assert True\n' > "$R/tests/test_regress.py"
printf '# debug patterns\n## Pattern 7 — sample\n' > "$R/.claude/debug-patterns.md"
gate "$R" t-reg-ok <<'EOF'
pr: local-only
diff_base: none — first build
baseline: pytest=n/a tsc=n/a
qa1: GO
qa2: GO
qa3: GO
integration_flow: n/a — docs-only
regression: yes — PROJ-999 founder-reported
regression_test: tests/test_regress.py
debug_pattern: .claude/debug-patterns.md#Pattern 7
gate_extension: not-needed: additive script, no runtime surface
decision: GO
signoff: qa3-clean
EOF
expect_rc 0 "regression:yes + full evidence → PASS"

# regression: yes but missing regression_test → BLOCKED
R=$(mkrepo)
gate "$R" t-reg-bad <<'EOF'
pr: local-only
diff_base: none — first build
baseline: pytest=n/a tsc=n/a
qa1: GO
qa2: GO
qa3: GO
integration_flow: n/a — docs-only
regression: yes — PROJ-1000
regression_test: n/a
debug_pattern: n/a
gate_extension: n/a
decision: GO
signoff: qa3-clean
EOF
expect_rc 1 "regression:yes missing evidence → BLOCKED"

# ============================================================
bold "ai-os-prune — stale worktree detection"
# ============================================================

# build a clone backed by a real (file://) origin so merge-base logic applies
mkorigin(){ # -> echoes work-clone path
  local o="$TMP_ROOT/origin.$RANDOM.git" w="$TMP_ROOT/work.$RANDOM"
  git init -q --bare "$o"
  git clone -q "$o" "$w" 2>/dev/null
  git -C "$w" config user.email t@t; git -C "$w" config user.name t
  git -C "$w" config commit.gpgsign false
  printf 'seed\n' > "$w/README"
  git -C "$w" add -A; git -C "$w" commit -qm seed
  git -C "$w" branch -M main 2>/dev/null || true
  git -C "$w" push -q -u origin main
  printf '%s' "$w"
}

# clean: only the main checkout, nothing stale
W=$(mkorigin)
run "$PRUNE" "$W"
expect_rc 0 "no extra worktrees → exit 0"
expect_out 'No stale task worktrees' "clean prune reports legible state"

# STALE (merged) + REVIEW (unpushed) in one repo
W=$(mkorigin)
# merged feature -> origin/main, with a lingering worktree on it
git -C "$W" checkout -q -b feature
printf 'f\n' >> "$W/feature.txt"; git -C "$W" add -A; git -C "$W" commit -qm feat
git -C "$W" push -q -u origin feature
git -C "$W" checkout -q main
git -C "$W" merge -q --ff-only feature
git -C "$W" push -q origin main
git -C "$W" worktree add -q "$TMP_ROOT/wt-feature.$RANDOM" feature 2>/dev/null
# unpushed wip branch with its own worktree
git -C "$W" worktree add -q -b wip "$TMP_ROOT/wt-wip.$RANDOM" main 2>/dev/null
WIPWT=$(git -C "$W" worktree list --porcelain | awk '/wt-wip/{print $2}')
git -C "$W" checkout -q main
# commit on wip via its worktree dir
WIPDIR=$(git -C "$W" worktree list | awk '/\[wip\]/{print $1}')
printf 'w\n' >> "$WIPDIR/wip.txt"
git -C "$WIPDIR" add -A; git -C "$WIPDIR" commit -qm wip
run "$PRUNE" "$W"
expect_rc 3 "stale + review worktrees → exit 3"
expect_out 'STALE' "merged worktree flagged STALE"
expect_out 'REVIEW' "unpushed worktree flagged REVIEW"

# ============================================================
bold "ai-os-lock — atomic acquire / release / liveness"
# ============================================================

# acquire a free slug, mirrored into LOCKS.md, and ai-os-status sees OWNED
R=$(mkrepo)
( cd "$R" && "$LOCK" acquire README "editing readme" ) >"$OUT" 2>&1; RC=$?
expect_rc 0 "acquire free slug → exit 0"
expect_out 'acquired' "acquire reports success"
if grep -q '\[LOCKED\] README' "$R/.ai/LOCKS.md"; then pass "LOCKS.md mirror written"; else fail "LOCKS.md mirror missing"; fi
printf 'edit\n' >> "$R/README"
run "$STATUS" "$R"
expect_out '\[OWNED.*README' "lock mirror → ai-os-status OWNED"

# re-acquire the held slug (different session) → refused
( cd "$R" && AI_OS_SESSION=other "$LOCK" acquire README "me too" ) >"$OUT" 2>&1; RC=$?
expect_rc 3 "acquire held slug → exit 3 (refused)"
expect_out 'HELD' "held slug names the owner"

# check reports HELD then FREE across release
( cd "$R" && "$LOCK" check README ) >"$OUT" 2>&1; RC=$?
expect_rc 3 "check held → exit 3"
( cd "$R" && "$LOCK" release README ) >"$OUT" 2>&1
( cd "$R" && "$LOCK" check README ) >"$OUT" 2>&1; RC=$?
expect_rc 0 "check after release → exit 0 (free)"
if grep -q 'No active locks' "$R/.ai/LOCKS.md"; then pass "release clears LOCKS.md mirror"; else fail "release left a stale mirror line"; fi

# dead-owner lock (pid provided, process gone) is reclaimable via reap
R=$(mkrepo)
( cd "$R" && AI_OS_AGENT_PID=2147483647 "$LOCK" acquire ghost "abandoned" ) >/dev/null 2>&1
( cd "$R" && "$LOCK" reap ) >"$OUT" 2>&1
expect_out "reaped 1 dead" "reap removes a dead-owner lock"
( cd "$R" && "$LOCK" check ghost ) >"$OUT" 2>&1; RC=$?
expect_rc 0 "reaped lock is free again"

# CONCURRENCY: two parallel acquires of one slug → exactly one winner
R=$(mkrepo)
( cd "$R" && AI_OS_SESSION=s1 "$LOCK" acquire race "A"; echo $? > "$TMP_ROOT/rc1" ) >/dev/null 2>&1 &
( cd "$R" && AI_OS_SESSION=s2 "$LOCK" acquire race "B"; echo $? > "$TMP_ROOT/rc2" ) >/dev/null 2>&1 &
wait
ZEROS=$(cat "$TMP_ROOT/rc1" "$TMP_ROOT/rc2" 2>/dev/null | grep -c '^0$')
THREES=$(cat "$TMP_ROOT/rc1" "$TMP_ROOT/rc2" 2>/dev/null | grep -c '^3$')
LINES=$(grep -c '\[LOCKED\]' "$R/.ai/LOCKS.md" 2>/dev/null || echo 0)
if [ "$ZEROS" -eq 1 ] && [ "$THREES" -eq 1 ]; then pass "race: exactly one acquire won (1×rc0, 1×rc3)"; else fail "race: rc0=$ZEROS rc3=$THREES (want 1/1)"; fi
if [ "$LINES" -eq 1 ]; then pass "race: exactly one LOCKS.md line (no lost update)"; else fail "race: $LINES LOCKS.md lines (want 1)"; fi

# ============================================================
bold "init-project — .ai/ excluded even from a linked worktree"
# ============================================================
# Regression for the --git-dir vs --git-common-dir bug: git reads info/exclude
# from the common dir, so running init from a worktree must still exclude .ai/.
# Isolate HOME/.ai-os: symlink ONLY bootstrap/ (for templates); projects.txt is
# created fresh in the temp dir so the test never pollutes the real hub registry.
LHOME="$TMP_ROOT/init-home"; mkdir -p "$LHOME/.ai-os"
ln -s "$HUB/bootstrap" "$LHOME/.ai-os/bootstrap"
W=$(mkorigin)
git -C "$W" worktree add -q -b initwt "$TMP_ROOT/wt-init.$RANDOM" main 2>/dev/null
WTDIR=$(git -C "$W" worktree list | awk '/initwt/{print $1}')
HOME="$LHOME" "$HUB/bootstrap/init-project.sh" "$WTDIR" >"$OUT" 2>&1
if git -C "$WTDIR" check-ignore -q .ai/LOCKS.md; then
  pass "init from worktree → .ai/ is git-ignored there"
else
  fail "init from worktree → .ai/ NOT ignored (info/exclude went to the wrong gitdir)"
  sed 's/^/        | /' "$OUT" >&2
fi

# ============================================================
bold "ai-os-watchdog — no false recovery capture on clean tree"
# ============================================================
# Regression: the watchdog grepped the WHOLE HANDOFF.md and matched the
# commented template example → captured recovery on cleanly-finished repos.
# Clean tree + only-commented in-progress + dead agent must NOT capture.
if command -v jq >/dev/null 2>&1; then
  WHOME="$TMP_ROOT/wd-home"; mkdir -p "$WHOME/.ai-os"
  R=$(mkrepo)                                    # clean tree, .ai/ excluded
  printf '%s\n' "$R" > "$WHOME/.ai-os/projects.txt"
  cat > "$R/.ai/HANDOFF.md" <<'EOF'
# Handoff — sample
---
<!-- template example — must NOT read as in-flight:
**Status:** in progress
-->
EOF
  printf '{"status":"ended","last_beat_epoch":1,"session_id":"s","agent":"claude","transcript_path":""}\n' \
    > "$R/.ai/heartbeat.json"
  find "$R/.ai" -exec touch -t 202601010000 {} + 2>/dev/null   # look "dead" (>30 min)
  HOME="$WHOME" bash "$HUB/bin/ai-os-watchdog.sh" >/dev/null 2>&1
  if [ -d "$R/.ai/recovery" ]; then
    fail "watchdog captured a CLEAN tree (commented HANDOFF false-positive)"
  else
    pass "watchdog ignores commented HANDOFF example on a clean tree"
  fi
else
  printf '  [note] jq not found; skipped watchdog test\n'
fi

# ============================================================
bold "ai-os-guard — PreToolUse lock guard (fail-open)"
# ============================================================
guard_edit(){ # repo path session [enforce] -> runs guard on an Edit of path
  local repo="$1" path="$2" sid="$3" enf="${4:-0}"
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/%s"},"session_id":"%s","cwd":"%s"}' \
    "$repo" "$path" "$sid" "$repo" | AI_OS_ENFORCE_LOCKS="$enf" "$GUARD" >"$OUT" 2>&1; RC=$?
}

# no locks → allow, silent
R=$(mkrepo)
guard_edit "$R" src/a.ts me
expect_rc 0 "guard: no locks → allow"
expect_no_out 'active lock' "guard silent when nothing locked"

# another agent's lock → fail-open warn (allow)
R=$(mkrepo)
( cd "$R" && AI_OS_SESSION=other "$LOCK" acquire "src/a.ts" "theirs" ) >/dev/null 2>&1
guard_edit "$R" src/a.ts me
expect_rc 0 "guard: cross-agent lock → fail-open allow (exit 0)"
expect_out 'under an active lock' "guard warns on cross-agent lock"

# enforce mode → block (exit 2)
guard_edit "$R" src/a.ts me 1
expect_rc 2 "guard: cross-agent lock + AI_OS_ENFORCE_LOCKS=1 → block (exit 2)"

# my OWN lock (session matches) → allow, silent
R=$(mkrepo)
( cd "$R" && AI_OS_SESSION=me "$LOCK" acquire "src/b.ts" "mine" ) >/dev/null 2>&1
guard_edit "$R" src/b.ts me
expect_rc 0 "guard: my own lock → allow"
expect_no_out 'under an active lock' "guard does not warn on my own lock"

# ============================================================
bold "ai-os-heartbeat — per-session beat files"
# ============================================================
if command -v jq >/dev/null 2>&1; then
  R=$(mkrepo)
  printf '{"hook_event_name":"SessionStart","cwd":"%s","session_id":"sess-xyz","transcript_path":""}' "$R" \
    | bash "$HUB/bin/ai-os-heartbeat.sh" >/dev/null 2>&1
  [ -f "$R/.ai/heartbeat.json" ]          && pass "heartbeat writes shared heartbeat.json" || fail "no shared heartbeat.json"
  [ -f "$R/.ai/heartbeat.sess-xyz.json" ] && pass "heartbeat writes per-session file"      || fail "no per-session heartbeat file"
  printf '{"hook_event_name":"SessionEnd","cwd":"%s","session_id":"sess-xyz","transcript_path":""}' "$R" \
    | bash "$HUB/bin/ai-os-heartbeat.sh" >/dev/null 2>&1
  [ ! -f "$R/.ai/heartbeat.sess-xyz.json" ] && pass "SessionEnd drops the per-session file" || fail "per-session file not cleaned on end"
else
  printf '  [note] jq not found; skipped heartbeat test\n'
fi

# ============================================================
printf '\n\033[1m# selftest summary\033[0m\n'
printf '  pass=%d  fail=%d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "ai-os-selftest: $FAIL behavioral assertion(s) failed" >&2
  exit 1
fi
echo "ai-os-selftest: all behavioral assertions passed"
