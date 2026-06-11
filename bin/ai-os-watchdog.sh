#!/usr/bin/env bash
# ai-os-watchdog.sh — runs hourly via launchd, independent of any agent, so it
# survives agent death. For every registered project it decides whether an agent
# went dark with un-preserved work, and if so captures that work NON-DESTRUCTIVELY
# (patches + untracked tarball — never commits/stashes/branches), writes a
# RECOVERY.md, queues a tracker filing for the next agent, and notifies the user.
#
# Registry: ~/.ai-os/projects.txt (one absolute repo path per line; # comments ok).
# Populated by bootstrap/init-project.sh.

set -uo pipefail
LOG="$HOME/.ai-os/.watchdog.log"
REG="$HOME/.ai-os/projects.txt"
STALE=4500          # 75 min with no heartbeat -> suspect dead
ALIVE_RECENT=1800   # transcript/.ai touched within 30 min -> still alive, skip
NOW=$(date +%s)
ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

log(){ echo "$(date -u +%FT%TZ) $*" >> "$LOG" 2>/dev/null || true; }
notify(){ osascript -e "display notification \"$1\" with title \"ai-os watchdog\"" >/dev/null 2>&1 || true; }
mtime(){ stat -f %m "$1" 2>/dev/null || echo 0; }
val(){ jq -r "$1 // empty" "$2" 2>/dev/null || echo ""; }

check_repo(){
  local repo="$1"; cd "$repo" 2>/dev/null || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local hb=".ai/heartbeat.json" status="" lastbeat=0 tpath="" sid="" sagent="claude"
  if [ -f "$hb" ]; then
    status=$(val '.status' "$hb"); tpath=$(val '.transcript_path' "$hb")
    sid=$(val '.session_id' "$hb"); sagent=$(val '.agent' "$hb")
    lastbeat=$(jq -r '.last_beat_epoch // 0' "$hb" 2>/dev/null || echo 0)
  fi

  # Liveness: a live agent leaves recent traces. Skip if any are fresh.
  local newest=0 m
  for f in "$tpath" .ai/heartbeat.json .ai/heartbeat.*.json .ai/HANDOFF.auto.md .ai/JOURNAL.md; do
    [ -n "$f" ] && [ -e "$f" ] && { m=$(mtime "$f"); [ "$m" -gt "$newest" ] && newest=$m; }
  done
  if [ "$newest" -gt 0 ] && [ $((NOW - newest)) -lt "$ALIVE_RECENT" ]; then
    return 0   # something touched recently -> agent alive (or just finished safely)
  fi
  if [ "$lastbeat" -gt 0 ] && [ $((NOW - lastbeat)) -lt "$STALE" ] && [ "$status" != "ended" ]; then
    return 0   # heartbeat still within tolerance
  fi

  # Is there anything worth preserving?
  local nfiles handoff_inflight=0
  nfiles=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  # positive signal: an agent that handed off mid-task wrote "in progress".
  # Only the ACTIVE region counts (after the first '---', before the '<!--'
  # template-example comment) — same parse as ai-os-status.sh. Grepping the
  # whole file matched the commented template example and captured recovery on
  # cleanly-finished repos (observed false positive; selftest covers it).
  if [ -f .ai/HANDOFF.md ]; then
    hbody=$(awk 'inb && /<!--/{exit} /^---[[:space:]]*$/{inb=1; next} inb' .ai/HANDOFF.md)
    printf '%s\n' "$hbody" | grep -qiE 'Status:[*: ]*in progress' && handoff_inflight=1
  fi
  if [ "${nfiles:-0}" -eq 0 ] && [ "$handoff_inflight" -eq 0 ]; then
    return 0   # clean tree, no in-flight handoff -> nothing lost
  fi

  # Dedupe: signature of the exact state. Skip if we already captured this.
  local head sig prev=""
  head=$(git rev-parse HEAD 2>/dev/null || echo none)
  sig="${lastbeat}:${head}:$(git diff 2>/dev/null | shasum 2>/dev/null | cut -c1-12)"
  [ -f .ai/.recovery-state ] && prev=$(cat .ai/.recovery-state 2>/dev/null || echo "")
  [ "$sig" = "$prev" ] && return 0

  # ---- Capture (non-destructive: copy/diff only, never mutate git) ----
  local rdir=".ai/recovery/$STAMP" branch reason
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  mkdir -p "$rdir"
  git diff               > "$rdir/work.patch"          2>/dev/null || true
  git diff --staged      > "$rdir/staged.patch"        2>/dev/null || true
  git diff HEAD          > "$rdir/tracked-all.patch"   2>/dev/null || true
  git status             > "$rdir/status.txt"          2>/dev/null || true
  git log --oneline -10  > "$rdir/recent-commits.txt"  2>/dev/null || true
  # untracked files are the easiest thing to lose — archive them verbatim
  git ls-files --others --exclude-standard -z 2>/dev/null \
    | xargs -0 -r tar -czf "$rdir/untracked.tgz" 2>/dev/null || true
  for f in .ai/HANDOFF.md .ai/HANDOFF.auto.md; do
    [ -f "$f" ] && cp "$f" "$rdir/" 2>/dev/null || true
  done
  tail -30 .ai/JOURNAL.md > "$rdir/journal-tail.txt" 2>/dev/null || true

  if [ "$status" = "ended" ]; then reason="session ended with work left behind"
  elif [ "$lastbeat" -gt 0 ]; then reason="no heartbeat for $(( (NOW-lastbeat)/60 )) min (agent likely killed)"
  else reason="no heartbeat file; dirty tree + in-flight handoff with no recent activity"; fi

  cat > "$rdir/RECOVERY.md" <<EOF
# Recovery capture — $ISO

**Repo:** $repo
**Branch:** $branch
**Last agent:** $sagent  (session $sid)
**Why flagged:** $reason
**Uncommitted files:** ${nfiles:-0}   **In-flight HANDOFF:** $([ "$handoff_inflight" -eq 1 ] && echo yes || echo no)

## This is a NON-DESTRUCTIVE capture
Your git state was NOT modified. Nothing was committed, stashed, or branched.
The work is preserved as patches + an untracked-file archive in this directory.

## Restore
\`\`\`bash
cd "$repo"
git apply .ai/recovery/$STAMP/tracked-all.patch     # tracked changes (staged+unstaged)
tar -xzf .ai/recovery/$STAMP/untracked.tgz           # untracked files (if any)
\`\`\`
(\`work.patch\` = unstaged only, \`staged.patch\` = staged only, if you need them split.)

## Tracker lifecycle (handled by the next agent)
linear_status: pending
The next agent that opens this repo MUST, per the AGENT-CONTRACT §Start:
1. Create/update an issue titled \`[ai-os recovery] $repo @ $branch\`
   with this RECOVERY.md content, then set \`linear_status: filed <issue-id>\` below.
2. If on inspection this was a FALSE POSITIVE (the work actually continued fine,
   or was already committed/handed off elsewhere): close that issue with a
   note "false positive — agent resumed normally", delete this recovery dir, and
   clear .ai/.recovery-state. Do not leave a phantom recovery issue open.

tracker_filed_issue:
EOF

  echo "$sig" > .ai/.recovery-state
  printf '%s ai-os-watchdog — RECOVERY captured: %s (%s). See .ai/recovery/%s/RECOVERY.md\n' \
    "$ISO" "$reason" "$branch" "$STAMP" >> .ai/JOURNAL.md 2>/dev/null || true
  if [ -f .ai/LOCKS.md ] && grep -q '\[LOCKED\]' .ai/LOCKS.md; then
    printf -- '- [STALE? watchdog %s] locks above may belong to a dead agent — verify before reuse\n' \
      "$ISO" >> .ai/LOCKS.md 2>/dev/null || true
  fi
  log "RECOVERY $repo @ $branch ($reason)"
  notify "Recovered abandoned work in $(basename "$repo") @ $branch — see .ai/recovery/"
}

[ -f "$REG" ] || exit 0
log "sweep start"
while IFS= read -r line; do
  repo="${line%%#*}"; repo="$(echo "$repo" | xargs 2>/dev/null || true)"
  [ -n "$repo" ] && [ -d "$repo/.git" ] && [ -d "$repo/.ai" ] || continue
  ( check_repo "$repo" ) 2>>"$LOG" || log "ERROR in $repo"
done < "$REG"
log "sweep end"
exit 0
