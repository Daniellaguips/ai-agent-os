#!/usr/bin/env bash
# ai-os-validate.sh - mechanical checks for the AI OS hub itself.
#
# Fast by default: validates shell syntax, skill layout/frontmatter, doc references,
# and link-skill behavior in an isolated temporary HOME. Pass --smoke to also run
# the clean-machine setup smoke test.
set -euo pipefail

HUB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUN_SMOKE=0
FAILS=0
TMP_ROOT=""

usage(){
  cat <<'EOF'
usage: ai-os-validate.sh [--smoke]

  --smoke   also run bin/ai-os-smoke-setup.sh
EOF
}

while [ "${1:-}" ]; do
  case "$1" in
    --smoke) RUN_SMOKE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

cleanup(){
  if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

ok(){ printf '[ok] %s\n' "$*"; }
fail(){ printf '[fail] %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }
note(){ printf '[note] %s\n' "$*"; }

portable_skill_dirs(){
  find "$HUB/skills" -mindepth 1 -maxdepth 1 -type d \
    ! -name project ! -name '.*' ! -name '_*' | while IFS= read -r dir; do
    [ -f "$dir/SKILL.md" ] && printf '%s\n' "$dir"
  done | sort
}

project_skill_dirs(){
  if [ -d "$HUB/skills/project" ]; then
    find "$HUB/skills/project" -mindepth 2 -maxdepth 2 -type d | while IFS= read -r dir; do
      [ -f "$dir/SKILL.md" ] && printf '%s\n' "$dir"
    done | sort
  fi
}

project_pack_dirs(){
  if [ -d "$HUB/skills/project" ]; then
    find "$HUB/skills/project" -mindepth 1 -maxdepth 1 -type d | sort
  fi
}

all_skill_dirs(){
  {
    portable_skill_dirs
    project_skill_dirs
  } | sort
}

check_shell_syntax(){
  local f
  while IFS= read -r f; do
    if bash -n "$f"; then
      ok "bash syntax: ${f#$HUB/}"
    else
      fail "bash syntax: ${f#$HUB/}"
    fi
  done < <(find "$HUB/bin" "$HUB/bootstrap" "$HUB/skills" -type f -name '*.sh' | sort)
}

check_executable_scripts(){
  local f
  while IFS= read -r f; do
    if [ -x "$f" ]; then
      ok "executable: ${f#$HUB/}"
    else
      fail "not executable: ${f#$HUB/}"
    fi
  done < <(find "$HUB/bin" -maxdepth 1 -type f -name '*.sh' | sort; printf '%s\n' "$HUB/bootstrap/init-project.sh")
}

frontmatter_value(){
  local key="$1" file="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm=1; next }
    in_fm && $0 == "---" { exit }
    in_fm && index($0, key ":") == 1 {
      sub("^" key ":[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}

check_skill_frontmatter(){
  local dir file expected name desc names_seen
  names_seen="$TMP_ROOT/skill-names.txt"
  : > "$names_seen"

  while IFS= read -r dir; do
    file="$dir/SKILL.md"
    expected="$(basename "$dir")"

    if [ "$(sed -n '1p' "$file")" != "---" ]; then
      fail "skill frontmatter starts with ---: ${file#$HUB/}"
      continue
    fi

    name="$(frontmatter_value name "$file")"
    desc="$(frontmatter_value description "$file")"

    if [ -z "$name" ]; then
      fail "skill missing name: ${file#$HUB/}"
    elif [ "$name" != "$expected" ]; then
      fail "skill name '$name' does not match directory '$expected': ${file#$HUB/}"
    elif grep -qxF "$name" "$names_seen"; then
      fail "duplicate skill name '$name'"
    else
      printf '%s\n' "$name" >> "$names_seen"
      ok "skill name: $name"
    fi

    if [ -z "$desc" ]; then
      fail "skill missing description: ${file#$HUB/}"
    else
      case "$desc" in
        *'<'*|*'>'*) fail "skill description contains angle brackets: ${file#$HUB/}" ;;
        *) ok "skill description: $name" ;;
      esac
    fi
  done < <(all_skill_dirs)
}

check_skill_layout(){
  local pack
  while IFS= read -r pack; do
    [ -z "$pack" ] && continue
    if [ -f "$pack/README.md" ]; then
      ok "project pack README: ${pack#$HUB/}"
    else
      fail "missing project pack README: ${pack#$HUB/}"
    fi
  done < <(project_pack_dirs)

  if [ ! -d "$HUB/skills/project" ]; then
    ok "no project packs present"
  fi
}

assert_link(){
  local path="$1" expected="$2"
  if [ ! -L "$path" ]; then
    fail "expected symlink: $path"
    return
  fi
  local got
  got="$(readlink "$path")"
  if [ "$got" = "$expected" ]; then
    ok "link: $path -> $expected"
  else
    fail "link target mismatch: $path -> $got (expected $expected)"
  fi
}

check_linker(){
  local home tool dir name expected first_pack pack_name first_skill
  home="$TMP_ROOT/link-home"
  mkdir -p "$home"
  ln -s "$HUB" "$home/.ai-os"

  HOME="$home" "$HUB/bin/link-skill.sh" --all >"$TMP_ROOT/link-all.out"
  HOME="$home" "$HUB/bin/link-skill.sh" --all >"$TMP_ROOT/link-all-2.out"
  if grep -q '^  relink ' "$TMP_ROOT/link-all-2.out"; then
    fail "link-skill --all is not idempotent"
  else
    ok "link-skill --all idempotent"
  fi

  while IFS= read -r dir; do
    name="$(basename "$dir")"
    expected="$home/.ai-os/skills/$name"
    for tool in .claude .codex; do
      assert_link "$home/$tool/skills/$name" "$expected"
    done
  done < <(portable_skill_dirs)

  while IFS= read -r dir; do
    name="$(basename "$dir")"
    for tool in .claude .codex; do
      if [ -e "$home/$tool/skills/$name" ]; then
        fail "project skill linked by --all: $tool/$name"
      else
        ok "project skill excluded by --all: $tool/$name"
      fi
    done
  done < <(project_skill_dirs)

  first_pack="$(project_pack_dirs | head -1 || true)"
  if [ -z "$first_pack" ]; then
    ok "no project packs to link"
    return
  fi

  pack_name="$(basename "$first_pack")"
  HOME="$home" "$HUB/bin/link-skill.sh" --project "$pack_name" >"$TMP_ROOT/link-project.out"
  HOME="$home" "$HUB/bin/link-skill.sh" --project "$pack_name" >"$TMP_ROOT/link-project-2.out"
  if grep -q '^  relink ' "$TMP_ROOT/link-project-2.out"; then
    fail "link-skill --project $pack_name is not idempotent"
  else
    ok "link-skill --project $pack_name idempotent"
  fi

  while IFS= read -r dir; do
    name="$(basename "$dir")"
    expected="$home/.ai-os/skills/project/$pack_name/$name"
    for tool in .claude .codex; do
      assert_link "$home/$tool/skills/$name" "$expected"
    done
  done < <(find "$first_pack" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r dir; do [ -f "$dir/SKILL.md" ] && printf '%s\n' "$dir"; done | sort)

  first_skill="$(find "$first_pack" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r dir; do [ -f "$dir/SKILL.md" ] && printf '%s\n' "$dir"; done | sort | head -1 || true)"
  if [ -n "$first_skill" ]; then
    name="$(basename "$first_skill")"
    HOME="$home" "$HUB/bin/link-skill.sh" "$name" >"$TMP_ROOT/link-one.out"
    assert_link "$home/.codex/skills/$name" "$home/.ai-os/skills/project/$pack_name/$name"
    assert_link "$home/.claude/skills/$name" "$home/.ai-os/skills/project/$pack_name/$name"
  fi
}

check_docs(){
  local f
  for f in README.md SETUP.md MINIMUM-AI-OS.md lessons.md skills/README.md; do
    if [ -f "$HUB/$f" ]; then
      ok "doc exists: $f"
    else
      fail "missing doc: $f"
    fi
  done

  grep -q 'bin/ai-os-validate.sh' "$HUB/README.md" \
    && ok "README mentions validator" \
    || fail "README does not mention validator"
  grep -q 'bin/ai-os-smoke-setup.sh' "$HUB/SETUP.md" \
    && ok "SETUP mentions clean-machine smoke" \
    || fail "SETUP does not mention clean-machine smoke"
}

check_quick_validate_if_available(){
  local qv dir
  qv=""
  for candidate in \
    "$HOME/.codex/skills/.system/skill-creator/scripts/quick_validate.py" \
    "$HOME/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator/scripts/quick_validate.py"; do
    if [ -f "$candidate" ]; then
      qv="$candidate"
      break
    fi
  done

  if [ -z "$qv" ]; then
    note "quick_validate.py not found; skipped"
    return
  fi

  while IFS= read -r dir; do
    if python3 "$qv" "$dir" >"$TMP_ROOT/quick-validate.out" 2>"$TMP_ROOT/quick-validate.err"; then
      ok "quick_validate: ${dir#$HUB/}"
    else
      cat "$TMP_ROOT/quick-validate.out" >&2 || true
      cat "$TMP_ROOT/quick-validate.err" >&2 || true
      fail "quick_validate: ${dir#$HUB/}"
    fi
  done < <(all_skill_dirs)
}

check_git_diff(){
  if git -C "$HUB" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$HUB" diff --check; then
      ok "git diff --check"
    else
      fail "git diff --check"
    fi
  fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-os-validate.XXXXXX")"

check_shell_syntax
check_executable_scripts
check_skill_frontmatter
check_skill_layout
check_linker
check_quick_validate_if_available
check_git_diff
check_docs

if [ "$RUN_SMOKE" -eq 1 ]; then
  if "$HUB/bin/ai-os-smoke-setup.sh"; then
    ok "clean-machine setup smoke"
  else
    fail "clean-machine setup smoke"
  fi
fi

if [ "$FAILS" -gt 0 ]; then
  echo "ai-os-validate: $FAILS failure(s)" >&2
  exit 1
fi

echo "ai-os-validate: all checks passed"
