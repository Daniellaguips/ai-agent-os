#!/usr/bin/env bash
# ai-os-smoke-setup.sh - clean-machine smoke test for setup-clone.sh.
#
# Creates a temporary HOME, clones this hub into HOME/.ai-os, runs setup-clone.sh,
# verifies portable skill links, checks optional project-pack opt-in, and bootstraps
# a sample repo. Nothing should write to the caller's real HOME.
set -euo pipefail

SOURCE_HUB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SMOKE_REF="${AI_OS_SMOKE_REF:-HEAD}"
AGENTS_REMOTE="${AI_OS_SMOKE_AGENTS_REMOTE:-${AI_OS_AGENTS_REMOTE:-https://github.com/Daniellaguips/agents.git}}"
KEEP="${AI_OS_SMOKE_KEEP:-0}"
TMP_ROOT=""

usage(){
  cat <<'EOF'
usage: ai-os-smoke-setup.sh

Environment:
  AI_OS_SMOKE_REF=<git-ref>              ref to checkout in the temp clone (default HEAD)
  AI_OS_SMOKE_AGENTS_REMOTE=<url|path>   debug-team repo source (default public agents repo)
  AI_OS_SMOKE_KEEP=1                     keep the temp directory for inspection
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

cleanup(){
  if [ "$KEEP" = "1" ] && [ -n "${TMP_ROOT:-}" ]; then
    echo "ai-os-smoke: kept temp dir: $TMP_ROOT"
    return
  fi
  if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

ok(){ printf '[ok] %s\n' "$*"; }
fail(){ printf '[fail] %s\n' "$*" >&2; exit 1; }
assert_file(){ [ -f "$1" ] && ok "file exists: $1" || fail "missing file: $1"; }
assert_dir(){ [ -d "$1" ] && ok "dir exists: $1" || fail "missing dir: $1"; }

assert_link(){
  local path="$1" expected="$2" got
  [ -L "$path" ] || fail "expected symlink: $path"
  got="$(readlink "$path")"
  [ "$got" = "$expected" ] || fail "link target mismatch: $path -> $got (expected $expected)"
  ok "link: $path -> $expected"
}

skill_dirs_at_root(){
  local hub="$1"
  find "$hub/skills" -mindepth 1 -maxdepth 1 -type d \
    ! -name project ! -name '.*' ! -name '_*' | while IFS= read -r dir; do
    [ -f "$dir/SKILL.md" ] && printf '%s\n' "$dir"
  done | sort
}

project_pack_dirs(){
  local hub="$1"
  if [ -d "$hub/skills/project" ]; then
    find "$hub/skills/project" -mindepth 1 -maxdepth 1 -type d | sort
  fi
}

project_skill_dirs(){
  local pack="$1"
  find "$pack" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r dir; do
    [ -f "$dir/SKILL.md" ] && printf '%s\n' "$dir"
  done | sort
}

if ! git -C "$SOURCE_HUB" diff --quiet || ! git -C "$SOURCE_HUB" diff --cached --quiet; then
  echo "[note] source hub has local changes; smoke tests a fresh clone of committed git state"
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-os-smoke.XXXXXX")"
SMOKE_HOME="$TMP_ROOT/home"
CLONE="$SMOKE_HOME/.ai-os"
SAMPLE="$TMP_ROOT/sample-repo"
mkdir -p "$SMOKE_HOME"

echo "ai-os-smoke: temp HOME=$SMOKE_HOME"
git clone --quiet "$SOURCE_HUB" "$CLONE"
if [ "$SMOKE_REF" != "HEAD" ]; then
  git -C "$CLONE" checkout -q "$SMOKE_REF"
fi
ok "fresh hub clone"

if [ -e "$CLONE/debug" ]; then
  fail "fresh clone unexpectedly has debug/"
else
  ok "fresh clone starts without debug/"
fi

HOME="$SMOKE_HOME" AI_OS_AGENTS_REMOTE="$AGENTS_REMOTE" "$CLONE/bin/setup-clone.sh"

assert_dir "$SMOKE_HOME/agents/.git"
assert_link "$CLONE/debug" "$SMOKE_HOME/agents"

while IFS= read -r dir; do
  name="$(basename "$dir")"
  for tool in .claude .codex; do
    assert_link "$SMOKE_HOME/$tool/skills/$name" "$SMOKE_HOME/.ai-os/skills/$name"
  done
done < <(skill_dirs_at_root "$CLONE")

FIRST_PACK="$(project_pack_dirs "$CLONE" | head -1 || true)"
if [ -n "$FIRST_PACK" ]; then
  PACK_NAME="$(basename "$FIRST_PACK")"
  while IFS= read -r dir; do
    name="$(basename "$dir")"
    for tool in .claude .codex; do
      if [ -e "$SMOKE_HOME/$tool/skills/$name" ]; then
        fail "project skill was linked during portable setup: $tool/$name"
      else
        ok "project skill absent before opt-in: $tool/$name"
      fi
    done
  done < <(project_skill_dirs "$FIRST_PACK")

  HOME="$SMOKE_HOME" "$CLONE/bin/link-skill.sh" --project "$PACK_NAME"
  while IFS= read -r dir; do
    name="$(basename "$dir")"
    for tool in .claude .codex; do
      assert_link "$SMOKE_HOME/$tool/skills/$name" "$SMOKE_HOME/.ai-os/skills/project/$PACK_NAME/$name"
    done
  done < <(project_skill_dirs "$FIRST_PACK")
else
  ok "no project packs present; opt-in project-pack check skipped"
fi

mkdir -p "$SAMPLE"
git -C "$SAMPLE" init -q
HOME="$SMOKE_HOME" "$CLONE/bootstrap/init-project.sh" "$SAMPLE"

for f in JOURNAL.md LOCKS.md HANDOFF.md DIRTY.md; do
  assert_file "$SAMPLE/.ai/$f"
done
assert_file "$SAMPLE/.ai/qa-gate/.keep"

grep -qxE '\.ai/?' "$SAMPLE/.git/info/exclude" \
  && ok "sample repo local exclude ignores .ai/" \
  || fail "sample repo local exclude does not ignore .ai/"

[ "$(git -C "$SAMPLE" config --get rerere.enabled || true)" = "true" ] \
  && ok "sample repo rerere enabled" \
  || fail "sample repo rerere not enabled"

SAMPLE_ABS="$(cd "$SAMPLE" && pwd -P)"
grep -qxF "$SAMPLE_ABS" "$CLONE/projects.txt" \
  && ok "sample repo registered with temp watchdog registry" \
  || fail "sample repo not registered with temp watchdog registry"

if [ -n "$(git -C "$SAMPLE" status --porcelain)" ]; then
  git -C "$SAMPLE" status --porcelain >&2
  fail "sample repo has tracked/unignored setup dirt"
else
  ok "sample repo has no tracked/unignored setup dirt"
fi

HOME="$SMOKE_HOME" "$CLONE/bin/ai-os-status.sh" "$SAMPLE" >"$TMP_ROOT/status.out"
ok "ai-os-status passes on bootstrapped sample repo"

echo "ai-os-smoke: clean-machine setup passed"
