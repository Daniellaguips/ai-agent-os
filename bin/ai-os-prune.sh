#!/usr/bin/env bash
# ai-os-prune.sh — READ-ONLY stale-worktree / branch reaper.
#
# Worktree sprawl is the single biggest "we don't know the exact state" leak:
# finished/abandoned task worktrees never get pruned, so `git worktree list`
# becomes unreadable and nobody can tell what is live. This reports which task
# worktrees are STALE (branch merged into origin/main or origin/codex/
# integration, or branch gone from origin) and prints the EXACT safe commands
# to retire each — archive-tag FIRST so the retire is always recoverable
# (never auto-deletes anything; v1 has no --exec).
#
# Harness-managed .claude/worktrees/agent-* are ignored (they are scratch the
# tool owns). The current worktree is never proposed for removal.
#
# Exit:  0 nothing stale  ·  3 stale worktrees found  ·  2 unusable
# Usage: ai-os-prune.sh [repo-path]      # default: current dir's repo

set -uo pipefail

REPO_ARG="${1:-$PWD}"
cd "$REPO_ARG" 2>/dev/null || { echo "ai-os-prune: cannot cd to $REPO_ARG" >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
  || { echo "ai-os-prune: $REPO_ARG is not a git repo" >&2; exit 2; }
cd "$ROOT"
HERE=$(git rev-parse --show-toplevel)

bold(){ printf '\033[1m%s\033[0m\n' "$*"; }

git fetch --prune --quiet origin 2>/dev/null || true

MERGE_BASES=""
for b in origin/main origin/codex/integration; do
  git rev-parse --verify --quiet "$b" >/dev/null 2>&1 && MERGE_BASES="$MERGE_BASES $b"
done

bold "ai-os-prune — stale task worktrees (read-only)"
echo "  merged-into bases:$MERGE_BASES"
echo

STALE=0; REVIEW=0
# `git worktree list --porcelain`: blocks of worktree/HEAD/branch lines.
WT=""; BRANCH=""
emit(){
  [ -z "$WT" ] && return
  case "$WT" in */.claude/worktrees/agent-*) WT=""; BRANCH=""; return;; esac
  if [ "$WT" = "$HERE" ]; then WT=""; BRANCH=""; return; fi   # never self

  local br="${BRANCH#refs/heads/}" reason="" tag

  # Protected trunks: never propose a branch delete or archive — only flag the
  # worktree itself as a redundant checkout the integrator can remove.
  case "$br" in
    main|master|codex/integration)
      STALE=$((STALE+1))
      echo "TRUNK  $WT"
      echo "       branch: $br   reason: redundant checkout of a protected trunk"
      echo "       retire (worktree only — NEVER delete/-archive a trunk branch):"
      echo "         git worktree remove \"$WT\""
      echo
      WT=""; BRANCH=""; return ;;
  esac

  if [ -z "$br" ]; then
    reason="detached HEAD (no branch) — verify nothing unsaved, then remove worktree"
  elif git rev-parse --verify --quiet "origin/$br" >/dev/null 2>&1; then
    for base in $MERGE_BASES; do
      if git merge-base --is-ancestor "origin/$br" "$base" 2>/dev/null; then
        reason="origin/$br merged into ${base#origin/}"; break
      fi
    done
  else
    for base in $MERGE_BASES; do
      if git merge-base --is-ancestor "$br" "$base" 2>/dev/null; then
        reason="merged into ${base#origin/}, no remote branch"; break
      fi
    done
    [ -z "$reason" ] && reason="REVIEW"   # no remote AND not merged → maybe unpushed work
  fi

  tag="archive/${br:-detached-$(basename "$WT")}"
  if [ "$reason" = "REVIEW" ]; then
    REVIEW=$((REVIEW+1))
    echo "REVIEW $WT"
    echo "       branch: $br   reason: no origin/$br AND not merged into a base"
    echo "       -> could be UNPUSHED live work. Confirm it's dead before retiring."
    echo "          If dead (archive tag captures the full branch — recoverable):"
    echo "            git tag $tag $br && git worktree remove \"$WT\" && git branch -D $br"
    echo
  elif [ -n "$reason" ]; then
    STALE=$((STALE+1))
    echo "STALE  $WT"
    echo "       branch: ${br:-<detached>}   reason: $reason"
    echo "       retire (recoverable — archive tag FIRST, no -f so a prior archive is never clobbered):"
    [ -n "$br" ] && echo "         git tag $tag $br"
    echo "         git worktree remove \"$WT\""
    [ -n "$br" ] && echo "         git branch -D $br   # restore later: git branch $br $tag"
    echo
  else
    echo "live   $WT  (${br:-<detached>})"
  fi
  WT=""; BRANCH=""
}

while IFS= read -r line; do
  case "$line" in
    worktree\ *) emit; WT="${line#worktree }";;
    branch\ *)   BRANCH="${line#branch }";;
    "")          emit;;
  esac
done < <(git worktree list --porcelain 2>/dev/null; echo)
emit

echo "------------------------------------------------------------"
if [ "$STALE" -eq 0 ] && [ "$REVIEW" -eq 0 ]; then
  echo "No stale task worktrees. State is legible."
  exit 0
else
  echo "STALE: $STALE (safe to retire — merged/trunk)   REVIEW: $REVIEW (confirm not unpushed live work)"
  echo "Archive tag (no -f) makes every retire recoverable. After retiring: git fetch --prune."
  exit 3
fi
