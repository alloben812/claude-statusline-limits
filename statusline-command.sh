#!/usr/bin/env bash
# Claude Code statusline — эквивалент поста nodge (Атушка post/4849970, раздел 4).
# Показывает: модель + длительность сессии · cost · ctx (с цветом) · cache · limits (подписка)
# · skills (сработало/загружено, данные от плагина skill-tracker; 24.09.2026).
# Подключается в ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" }

input=$(cat)

# --- ANSI ---
RST=$'\033[0m'; DIM=$'\033[2m'; CYAN=$'\033[36m'; MAG=$'\033[35m'
GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; GRY=$'\033[90m'

# --- достаём поля одним jq (tab-separated) ---
vals=$(printf '%s' "$input" | jq -r '
  [ (.session_id // "-"),
    (.model.display_name // "?"),
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

IFS=$'\t' read -r sid model dur_ms cost ctx cache l5 r5 l7 r7 <<< "$vals"

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

# --- цвет процента (зелёный <50, жёлтый <80, красный выше) ---
pct_col() {
  if   (( $1 < 50 )); then printf '%s' "$GRN"
  elif (( $1 < 80 )); then printf '%s' "$YEL"
  else printf '%s' "$RED"; fi
}

# --- радужная полоска: bar <процент> ---
# Десять клеток, закрашенных фоном: фон заливает клетку на всю высоту строки,
# а символы-блоки Apple Terminal рисует шрифтом, и они выходят ниже строки.
# Цвет клетки зависит от её места, поэтому к 100% полоска проходит всю радугу
# от красного до фиолетового. Пустые клетки ровные серые: цветная пустая часть
# читалась как данные. Палитра 256 цветов: Apple Terminal не умеет truecolor.
# По умолчанию под тёмный фон; для светлого терминала STATUSLINE_THEME=light.
RAINBOW=(196 202 214 220 148 40 44 33 57 129)
if [[ "${STATUSLINE_THEME:-}" == light ]]; then TRACK=252; else TRACK=236; fi
bar() {
  local p=${1%.*} w=${#RAINBOW[@]} i n out=""
  [[ -z "$p" ]] && p=0
  (( p < 0 )) && p=0
  (( p > 100 )) && p=100
  n=$(( (p * w + 50) / 100 ))    # до ближайшей клетки
  (( p > 0 && n == 0 )) && n=1   # ненулевой расход видно всегда
  for (( i = 0; i < w; i++ )); do
    if (( i < n )); then out+=$'\033[48;5;'"${RAINBOW[i]}m "
    else out+=$'\033[48;5;'"${TRACK}m "; fi
  done
  printf '%s%s' "$out" "$RST"
}

ctx_int=${ctx%.*}; [[ -z "$ctx_int" ]] && ctx_int=0
ctx_col=$(pct_col "$ctx_int")

# --- собираем сегменты ---
seg=()
seg+=("${CYAN}${model}${RST} ${DIM}$(fmt_dur "$dur_ms")${RST}")
seg+=("${GRY}\$$(printf '%.3f' "$cost")${RST}")
seg+=("ctx $(bar "$ctx_int") ${ctx_col}${ctx_int}%${RST}")
seg+=("${DIM}cache $(fmt_tokens "${cache%.*}")${RST}")

# limits — только в режиме подписки (поля есть)
if [[ -n "$l5" ]]; then
  p5=$(printf '%.0f' "$l5")
  lim="${GRY}5h${RST} $(bar "$p5") $(pct_col "$p5")${p5}%${RST}"
  [[ -n "$r5" ]] && lim+=" ${DIM}($(fmt_left $(( r5 - now )) ))${RST}"
  if [[ -n "$l7" ]]; then
    p7=$(printf '%.0f' "$l7")
    lim+="${DIM} · ${RST}${GRY}7d${RST} $(bar "$p7") $(pct_col "$p7")${p7}%${RST}"
    [[ -n "$r7" ]] && lim+=" ${DIM}($(fmt_left $(( r7 - now )) ))${RST}"
  fi
  seg+=("$lim")
fi

# skills — сколько скиллов сработало за сессию из скольких загружено.
# Журнал ~/.claude/skill-log/<session_id>.txt и кеш .loaded-count пишет плагин
# skill-tracker; без плагина файлов нет и сегмент не показывается.
slog="$HOME/.claude/skill-log"
loaded=$(cat "$slog/.loaded-count" 2>/dev/null)
fired=()
if [[ -r "$slog/$sid.txt" ]]; then
  while IFS= read -r s; do [[ -n "$s" ]] && fired+=("${s##*:}"); done < "$slog/$sid.txt"
fi
nf=${#fired[@]}
if [[ -n "$loaded" ]] || (( nf > 0 )); then
  sk="skills ${nf}"
  [[ -n "$loaded" ]] && sk+="/${loaded}"
  if (( nf > 0 )); then
    # последние три, чтобы строка не разъезжалась; отрицательный сдвиг
    # при нехватке элементов даёт пустоту, поэтому считаем начало явно
    shown=("${fired[@]:$(( nf > 3 ? nf - 3 : 0 ))}")
    names=$(printf '%s, ' "${shown[@]}"); names=${names%, }
    (( nf > 3 )) && names="+$(( nf - 3 )) ${names}"
    sk+=" ${DIM}${names}${RST}"
  fi
  seg+=("${MAG}${sk}${RST}")
fi

# --- вывод через разделитель ---
out=""
for s in "${seg[@]}"; do
  [[ -n "$out" ]] && out+="${DIM} · ${RST}"
  out+="$s"
done
printf '%s' "$out"
