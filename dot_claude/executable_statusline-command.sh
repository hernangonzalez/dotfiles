#!/bin/bash
# Status line: [Model] dir | branch | Context: N% | +added -removed
input=$(cat)

# One jq call for all fields (tab-separated)
IFS=$'\t' read -r model dir used added removed < <(
  echo "$input" | jq -r '[
    .model.display_name // "?",
    (.workspace.current_dir // .cwd // ""),
    (.context_window.used_percentage // -1),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0)
  ] | @tsv'
)

if [ "$dir" = "$HOME" ]; then name="~"; else name="${dir##*/}"; fi
[ -z "$name" ] && name="/"
out="[$model] $name"

branch=$(git -C "$dir" branch --show-current 2>/dev/null)
[ -n "$branch" ] && out+=" | $branch"

if [ "${used%%.*}" -ge 0 ] 2>/dev/null; then
  u=$(printf '%.0f' "$used")
  if   [ "$u" -ge 80 ]; then c='\033[31m'
  elif [ "$u" -ge 50 ]; then c='\033[33m'
  else                       c='\033[32m'
  fi
  out+=$(printf ' | Context: %b%s%%\033[0m' "$c" "$u")
fi

out+=$(printf ' | \033[32m+%s\033[0m \033[31m-%s\033[0m' "$added" "$removed")
printf '%s' "$out"
