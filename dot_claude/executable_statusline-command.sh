#!/bin/bash
# Status line:
#   Model · effort · ▰▰▱▱ ctx% │ repo/sub/dir │ branch │ ✎prompt +ctx →out 🧠think% 🔧tools
# The last section describes the latest prompt only (see turn stats below).
input=$(cat)

# One jq call for all fields (tab-separated)
IFS=$'\t' read -r model dir effort used transcript < <(
  echo "$input" | jq -r '[
    .model.display_name // "?",
    (.workspace.current_dir // .cwd // ""),
    (.effort.level // "-"),
    (.context_window.used_percentage // -1),
    (.transcript_path // "")
  ] | @tsv'
)

R='\033[0m'
DIM='\033[38;5;245m'
SEP=$(printf ' %b│%b ' '\033[38;5;240m' "$R")
DOT=$(printf ' %b·%b ' "$DIM" "$R")

# 1234 -> 1.2k, 11234 -> 11k, 1234567 -> 1.2M
human() {
  awk -v n="$1" 'BEGIN {
    if (n < 1000) printf "%d", n
    else if (n < 10000) printf "%.1fk", n / 1000
    else if (n < 1000000) printf "%dk", n / 1000
    else printf "%.1fM", n / 1000000
  }'
}

# --- Model · effort · context bar ---
out=$(printf '%b%s%b' "$DIM" "$model" "$R")

# Effort shown only when not the default (medium)
if [ "$effort" != "-" ] && [ "$effort" != "medium" ]; then
  case "$effort" in
    low)    ec='\033[36m' ;;
    high)   ec='\033[33m' ;;
    xhigh)  ec='\033[35m' ;;
    max)    ec='\033[31m' ;;
    *)      ec='' ;;
  esac
  out+="$DOT"$(printf '%b%s%b' "$ec" "$effort" "$R")
fi

if [ "${used%%.*}" -ge 0 ] 2>/dev/null; then
  u=$(printf '%.0f' "$used")
  if   [ "$u" -ge 80 ]; then on='\033[38;5;210m'; off='\033[38;5;52m'
  elif [ "$u" -ge 50 ]; then on='\033[38;5;222m'; off='\033[38;5;58m'
  else                       on='\033[38;5;150m'; off='\033[38;5;22m'
  fi
  width=10
  filled=$(( (u * width + 50) / 100 ))
  [ "$u" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
  bar=""
  for ((i = 0; i < width; i++)); do
    # Braces matter: bash 3.2 otherwise reads █'s first byte as part of the name
    if [ "$i" -lt "$filled" ]; then bar+="${on}█"; else bar+="${off}█"; fi
  done
  out+="$DOT"$(printf '%b%b %b%s%%%b' "$bar" "$R" "$on" "$u" "$R")
fi

# --- Directory: repo-name/path/inside/repo, else ~-relative path ---
top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$top" ]; then
  path="${top##*/}${dir#"$top"}"
else
  path="${dir/#$HOME/~}"
fi
out+="$SEP"$(printf '%b%s%b' "$DIM" "$path" "$R")

# --- Branch ---
branch=$(git -C "$dir" branch --show-current 2>/dev/null)
[ -n "$branch" ] && out+="$SEP"$(printf '%b%s%b' "$DIM" "$branch" "$R")

# --- Turn stats for the latest prompt, from the transcript ---
#   ✎  prompt size: its text at ~4 chars/token (estimate)
#   +  what that prompt actually added to the context: input tokens of the first
#      response minus everything the context held after the previous response
#      (picks up images, pasted files, reminders, hook output)
#   →  output tokens across every response to the prompt
#   🧠 share of that output spent thinking. Thinking text is redacted in the
#      transcript, so it is output minus visible text and tool input at ~4 chars/token
#   🔧 tool calls made for the prompt
# A response is split over several lines sharing a message id, each carrying
# the same usage, so output is counted once per id.
prompt=-1; added=-1; out_tok=0; think=-1; tools=0
if [ -f "$transcript" ]; then
  IFS=$'\t' read -r prompt added out_tok think tools < <(
    jq -rn '
      def is_prompt:
        .type == "user" and .isMeta != true and
        (.message.content | if type == "string" then (startswith("<local-command-") | not)
         else (any(.[]?; .type == "tool_result") | not) and any(.[]?; .type == "text") end);
      reduce (inputs | select(.isSidechain != true)) as $e (
        {ctx: 0, base: 0, prompt: -1, first: null, out: 0, vis: 0, tools: 0, seen: {}};
        if ($e | is_prompt) then
          .base = .ctx | .first = null | .out = 0 | .vis = 0 | .tools = 0 | .seen = {}
          | .prompt = ($e.message.content
              | if type == "string" then length else [.[] | select(.type == "text") | .text | length] | add end)
        elif $e.type == "assistant" and $e.message.usage != null then
          $e.message.usage as $u
          | ($u.input_tokens + ($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0)) as $in
          | .first //= $in
          | (if .seen[$e.message.id] then . else .out += $u.output_tokens | .seen[$e.message.id] = true end)
          | .ctx = $in + $u.output_tokens
          | reduce ($e.message.content[]?) as $c (.;
              if $c.type == "text" then .vis += ($c.text | length)
              elif $c.type == "tool_use" then .tools += 1 | .vis += ($c.input | tojson | length)
              else . end)
        else . end)
      | [(if .prompt < 0 then -1 else .prompt / 4 | ceil end),
         (if .first == null then -1 else .first - .base end),
         .out,
         (if .out > 0 then ([.out - .vis / 4, 0] | max) * 100 / .out | round else -1 end),
         .tools]
      | @tsv' "$transcript" 2>/dev/null
  )
fi

# Each item hidden until it has a value (e.g. + appears with the first response)
stats=()
[ "${prompt:--1}" -ge 0 ] && stats+=("✎$(human "$prompt")")
[ "${added:--1}" -ge 0 ]  && stats+=("+$(human "$added")")
[ "${out_tok:-0}" -gt 0 ] && stats+=("→$(human "$out_tok")")
[ "${think:--1}" -ge 0 ]  && stats+=("🧠$think%")
[ "${tools:-0}" -gt 0 ]   && stats+=("🔧$tools")

[ ${#stats[@]} -gt 0 ] && out+="$SEP"$(printf '%b%s%b' "$DIM" "${stats[*]}" "$R")

printf '%s' "$out"
