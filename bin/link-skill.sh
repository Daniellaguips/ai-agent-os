#!/usr/bin/env bash
# link-skill.sh — make a hub skill usable by both Claude and Codex.
# Portable skills live canonically in ~/.ai-os/skills/<name>. Project-pack skills
# live in ~/.ai-os/skills/project/<pack>/<name>. This symlinks them into each
# tool's skills dir so either tool runs/improves the same copy.
#
# Usage:  ~/.ai-os/bin/link-skill.sh <skill-name>      # link one
#         ~/.ai-os/bin/link-skill.sh --all             # link portable skills
#         ~/.ai-os/bin/link-skill.sh --project <pack>  # link one project pack
set -euo pipefail
HUB="$HOME/.ai-os/skills"
TARGETS=("$HOME/.claude/skills" "$HOME/.codex/skills")

usage(){
  echo "usage: link-skill.sh <skill-name> | --all | --project <pack>"
}

is_skill_dir(){
  [ -d "$1" ] && [ -f "$1/SKILL.md" ]
}

find_skill_src(){
  local name="$1"
  if is_skill_dir "$HUB/$name"; then
    printf '%s\n' "$HUB/$name"
    return 0
  fi

  local match="" count=0 path
  if [ -d "$HUB/project" ]; then
    while IFS= read -r path; do
      match="$(dirname "$path")"
      count=$((count + 1))
    done < <(find "$HUB/project" -mindepth 3 -maxdepth 3 -path "*/$name/SKILL.md" -print)
  fi

  if [ "$count" -eq 1 ]; then
    printf '%s\n' "$match"
    return 0
  fi
  if [ "$count" -gt 1 ]; then
    echo "  skip: ambiguous project skill '$name'" >&2
    return 1
  fi
  return 1
}

link_src(){
  local name="$1" src="${2%/}"
  for d in "${TARGETS[@]}"; do
    mkdir -p "$d"
    local dst="$d/$name"
    if [ -L "$dst" ]; then
      [ "$(readlink "$dst")" = "$src" ] && { echo "  ok    $dst"; continue; }
      ln -sfn "$src" "$dst"; echo "  relink $dst"
    elif [ -e "$dst" ]; then
      mv "$dst" "$dst.prelink-$(date +%s)"
      ln -sfn "$src" "$dst"; echo "  linked $dst (real dir backed up as *.prelink-*)"
    else
      ln -sfn "$src" "$dst"; echo "  linked $dst"
    fi
  done
}

link_one(){
  local name="$1" src
  src="$(find_skill_src "$name")" || { echo "  skip: no hub skill '$name'"; return; }
  link_src "$name" "$src"
}

link_all_portable(){
  local s name
  for s in "$HUB"/*/; do
    [ -d "$s" ] || continue
    name="$(basename "$s")"
    case "$name" in
      project|_*) continue ;;
    esac
    is_skill_dir "$s" && link_src "$name" "$s"
  done
}

link_project(){
  local pack="$1" root="$HUB/project/$1" s
  [ -d "$root" ] || { echo "  skip: no project pack '$pack'"; return; }
  for s in "$root"/*/; do
    is_skill_dir "$s" && link_src "$(basename "$s")" "$s"
  done
}

if [ "${1:-}" = "--all" ]; then
  link_all_portable
elif [ "${1:-}" = "--project" ]; then
  [ -n "${2:-}" ] || { usage; exit 1; }
  link_project "$2"
elif [ -n "${1:-}" ]; then
  link_one "$1"
else
  usage
  exit 1
fi
