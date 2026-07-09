#!/usr/bin/env bash
# Claude Code statusline — эквивалент поста nodge (Атушка post/4849970, раздел 4).
# Показывает: модель + длительность сессии · cost · ctx (с цветом) · cache · limits (подписка).
# Подключается в ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" }

input=$(cat)

# --- ANSI ---
RST=$'\033[0m'; DIM=$'\033[2m'; CYAN=$'\033[36m'
GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; GRY=$'\033[90m'

# --- достаём поля одним jq (tab-separated) ---
vals=$(printf '%s' "$input" | jq -r '
  [ (.model.display_name // "?"),
    (.cost.total_duration_ms // 0),
    (.cost.total_cost_usd // 0),
    (.context_window.used_percentage // 0),
    ((.context_window.current_usage.cache_read_input_tokens // 0)
      + (.context_window.current_usage.cache_creation_input_tokens // 0)),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // "")
  ] | @tsv' 2>/dev/null)

IFS=$'\t' read -r model dur_ms cost ctx cache l5 r5 l7 r7 <<< "$vals"

now=$(date +%s)

# --- длительность сессии ---
fmt_dur() { # ms -> человекочитаемо
  local s=$(( ${1%.*} / 1000 )) h m
  h=$(( s/3600 )); m=$(( (s%3600)/60 )); s=$(( s%60 ))
  if   (( h > 0 )); then printf '%dh %dm' "$h" "$m"
  elif (( m > 0 )); then printf '%dm %ds' "$m" "$s"
  else printf '%ds' "$s"; fi
}

fmt_left() { # секунды до сброса -> человекочитаемо
  local s=$1 d h m
  (( s < 0 )) && s=0
  d=$(( s/86400 )); h=$(( (s%86400)/3600 )); m=$(( (s%3600)/60 ))
  if   (( d > 0 )); then printf '%dd %dh' "$d" "$h"
  elif (( h > 0 )); then printf '%dh %dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

fmt_tokens() { # число -> k/M
  awk -v n="$1" 'BEGIN{
    if (n>=1000000) printf "%.1fM", n/1000000;
    else if (n>=1000) printf "%.1fk", n/1000;
    else printf "%d", n }'
}

# --- ctx с цветом (зелёный <50, жёлтый <80, красный выше) ---
ctx_int=${ctx%.*}; [[ -z "$ctx_int" ]] && ctx_int=0
if   (( ctx_int < 50 )); then ctx_col=$GRN
elif (( ctx_int < 80 )); then ctx_col=$YEL
else ctx_col=$RED; fi

# --- собираем сегменты ---
seg=()
seg+=("${CYAN}${model}${RST} ${DIM}$(fmt_dur "$dur_ms")${RST}")
seg+=("${GRY}\$$(printf '%.3f' "$cost")${RST}")
seg+=("ctx ${ctx_col}${ctx_int}%${RST}")
seg+=("${DIM}cache $(fmt_tokens "${cache%.*}")${RST}")

# limits — только в режиме подписки (поля есть)
if [[ -n "$l5" ]]; then
  lim="5h $(printf '%.0f' "$l5")%"
  [[ -n "$r5" ]] && lim+=" ${DIM}($(fmt_left $(( r5 - now )) ))${RST}"
  if [[ -n "$l7" ]]; then
    lim+=" · 7d $(printf '%.0f' "$l7")%"
    [[ -n "$r7" ]] && lim+=" ${DIM}($(fmt_left $(( r7 - now )) ))${RST}"
  fi
  seg+=("${GRY}${lim}${RST}")
fi

# --- вывод через разделитель ---
out=""
for s in "${seg[@]}"; do
  [[ -n "$out" ]] && out+="${DIM} · ${RST}"
  out+="$s"
done
printf '%s' "$out"
