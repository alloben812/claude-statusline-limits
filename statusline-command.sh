#!/usr/bin/env bash
# Claude Code statusline в две строки (макет 24.09.2026):
#   Opus 5.5 (1M context)  my-project  ▇░░░░░░░░░░░░░ 9%  94k/1M  $1.28  2h12m  cache 92k  5h 4% 2h56m  7d 21% 5h56m
#   skills 1/74  statusline-limits
# Первая строка: модель · папка · контекст полоской, процентом и токенами · cost
# · длительность · cache · лимиты подписки 5h/7d с временем до сброса.
# Вторая: сколько скиллов сработало в сессии из скольких доступно и их имена.
# Подключается в ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" }

# Русская локаль ждёт в printf десятичную запятую, а JSON отдаёт точку
export LC_ALL=C

input=$(cat)

# --- цвета: палитра 256, Apple Terminal не умеет truecolor ---
# По умолчанию под тёмный фон; для светлого терминала STATUSLINE_THEME=light.
# RAMP — градиент полоски по месту клетки: зелёный до половины, дальше жёлтый,
# оранжевый и к концу красный. Число клеток равно длине массива.
if [[ "${STATUSLINE_THEME:-}" == light ]]; then
  C_MODEL=26; C_DIR=30; C_LBL=244; C_SKILL=127; C_TRACK=250
  RAMP=(28 28 64 64 100 100 136 136 172 172 166 166 160 124)
else
  C_MODEL=111; C_DIR=79; C_LBL=244; C_SKILL=170; C_TRACK=240
  RAMP=(78 78 113 113 149 149 185 221 220 214 208 202 196 160)
fi
RST=$'\033[0m'; BOLD=$'\033[1m'
fg() { printf '\033[38;5;%sm' "$1"; }
LBL=$(fg "$C_LBL")

# --- достаём поля одним jq; разделитель \x1f, потому что табы read склеивает ---
vals=$(printf '%s' "$input" | jq -r '
  [ (.session_id // "-"),
    (.transcript_path // ""),
    (.model.display_name // "?"),
    (.workspace.current_dir // .cwd // ""),
    (.workspace.project_dir // .cwd // ""),
    (.cost.total_duration_ms // 0),
    (.cost.total_cost_usd // 0),
    (.context_window.used_percentage // 0),
    ((.context_window.current_usage // {})
      | (.input_tokens // 0) + (.cache_creation_input_tokens // 0)
        + (.cache_read_input_tokens // 0)),
    (.context_window.context_window_size // 0),
    ((.context_window.current_usage.cache_read_input_tokens // 0)
      + (.context_window.current_usage.cache_creation_input_tokens // 0)),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // "")
  ] | map(tostring) | join("\u001f")' 2>/dev/null)

IFS=$'\x1f' read -r sid tpath model cwd proj dur_ms cost ctx used size cache l5 r5 l7 r7 <<< "$vals"
: "${model:=?}" "${dur_ms:=0}" "${cost:=0}" "${used:=0}" "${size:=0}" "${cache:=0}"

now=$(date +%s)

# --- форматирование ---
fmt_dur() { # мс -> 2h12m / 12m / 45s
  local s=$(( ${1%.*} / 1000 )) h m
  h=$(( s / 3600 )); m=$(( s % 3600 / 60 ))
  if   (( h > 0 )); then printf '%dh%dm' "$h" "$m"
  elif (( m > 0 )); then printf '%dm' "$m"
  else printf '%ds' "$s"; fi
}

fmt_left() { # секунды до сброса -> 3d11h / 2h56m / 42m
  local s=$1 d h m
  (( s < 0 )) && s=0
  d=$(( s / 86400 )); h=$(( s % 86400 / 3600 )); m=$(( s % 3600 / 60 ))
  if   (( d > 0 )); then printf '%dd%dh' "$d" "$h"
  elif (( h > 0 )); then printf '%dh%dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

fmt_tok() { # 94419 -> 94k, 1000000 -> 1M, 1500000 -> 1.5M
  local n=${1%.*} t
  [[ -z "$n" ]] && n=0
  if (( n >= 999500 )); then
    t=$(( (n + 50000) / 100000 ))   # десятые доли миллиона
    if (( t % 10 == 0 )); then printf '%dM' $(( t / 10 ))
    else printf '%d.%dM' $(( t / 10 )) $(( t % 10 )); fi
  elif (( n >= 1000 )); then printf '%dk' $(( (n + 500) / 1000 ))
  else printf '%d' "$n"; fi
}

to_int() { # 8.4 -> 8, пусто -> 0
  local v; v=$(printf '%.0f' "${1:-0}" 2>/dev/null) || v=0
  printf '%s' "${v:-0}"
}

BAR_W=${#RAMP[@]}

# сколько клеток закрашено при таком проценте
cells() {
  local p=$1 n
  (( p > 100 )) && p=100
  n=$(( (p * BAR_W + 50) / 100 ))   # до ближайшей клетки
  (( p > 0 && n == 0 )) && n=1      # ненулевой расход видно всегда
  printf '%s' "$n"
}

# цвет процента: цвет последней закрашенной клетки, при 0% — первой
lvl() {
  local n; n=$(cells "$1")
  (( n > 0 )) && n=$(( n - 1 ))
  printf '%s' "${RAMP[n]}"
}

# --- полоска контекста: bar <процент> ---
# Клетки закрашены фоном: фон заливает клетку на всю высоту строки, а символы-
# блоки Apple Terminal рисует шрифтом, и они выходят ниже строки. Цвет клетки
# зависит от её места, поэтому при заполнении зелёный переходит в жёлтый и
# красный. Пустая часть — штриховка ░ приглушённым цветом.
bar() {
  local n i out=""
  n=$(cells "$1")
  for (( i = 0; i < BAR_W; i++ )); do
    if (( i < n )); then out+=$'\033[48;5;'"${RAMP[i]}m "
    else
      (( i == n )) && out+="${RST}$(fg "$C_TRACK")"
      out+="░"
    fi
  done
  printf '%s%s' "$out" "$RST"
}

# --- первая строка ---
ctx_i=$(to_int "$ctx"); ctx_c=$(lvl "$ctx_i")
seg=()
seg+=("${BOLD}$(fg "$C_MODEL")${model}${RST}")
[[ -n "$cwd" ]] && seg+=("$(fg "$C_DIR")${cwd##*/}${RST}")
seg+=("$(bar "$ctx_i") $(fg "$ctx_c")${ctx_i}%${RST}")
if (( ${size%.*} > 0 )); then
  seg+=("$(fmt_tok "$used")${LBL}/$(fmt_tok "$size")${RST}")
fi
seg+=("$(printf '$%.2f' "$cost")")
seg+=("$(fmt_dur "$dur_ms")")
seg+=("${LBL}cache${RST} $(fmt_tok "$cache")")

# лимиты: только на подписке, на API-биллинге полей нет
lim() { # lim <метка> <процент> <resets_at>
  local p c
  p=$(to_int "$2"); c=$(lvl "$p")
  printf '%s%s%s %s%s%%%s' "$LBL" "$1" "$RST" "$(fg "$c")" "$p" "$RST"
  [[ -n "$3" ]] && printf ' %s%s%s' "$LBL" "$(fmt_left $(( ${3%.*} - now )))" "$RST"
}
[[ -n "$l5" ]] && seg+=("$(lim 5h "$l5" "$r5")")
[[ -n "$l7" ]] && seg+=("$(lim 7d "$l7" "$r7")")

line1=""
for s in "${seg[@]}"; do
  [[ -n "$line1" ]] && line1+="  "
  line1+="$s"
done

# --- вторая строка: скиллы ---
# Сработавшие скиллы берём из транскрипта сессии, в порядке первого появления:
#  - вызов инструмента Skill: "name":"Skill","input":{"skill":"X"};
#  - скилл, загруженный командой (набрал /X или его подгрузил сам Claude Code):
#    сообщение начинается с <command-message>X</command-message>\n<command-name>.
#    Встроенные /model, /effort, /clear пишутся в обратном порядке тегов
#    и сюда не попадают.
# В транскрипте текст экранирован, поэтому эти же строки внутри вывода команд
# (\"content\":...) шаблон не ловят. Дополнительно читаем журнал плагина
# skill-tracker ~/.claude/skill-log/<session_id>.txt: туда попадают и вызовы
# из субагентов, у которых свой транскрипт. grep по 10 МБ — около 12 мс.
slog="$HOME/.claude/skill-log"
fired=()
add_skill() {
  local s=${1##*:} x   # plugin:skill -> skill
  [[ -z "$s" ]] && return
  for x in "${fired[@]}"; do [[ "$x" == "$s" ]] && return; done
  fired+=("$s")
}
if [[ -n "$tpath" && -r "$tpath" ]]; then
  while IFS= read -r s; do add_skill "$s"; done < <(
    grep -oE '"name":"Skill","input":\{[^}]*"skill":"[^"]+"|"(content|text)":"<command-message>[^<]*</command-message>\\n<command-name>[^<]+</command-name>' "$tpath" 2>/dev/null |
    sed -E -e 's/.*"skill":"([^"]+)"$/\1/' -e 's|.*<command-name>/?([^<]+)</command-name>$|\1|')
fi
if [[ -r "$slog/$sid.txt" ]]; then
  while IFS= read -r s; do add_skill "$s"; done < "$slog/$sid.txt"
fi

# Сколько доступно: плагины и личные скиллы считает skill-tracker на старте
# сессии (.loaded-count); личные команды и всё проектное добавляем здесь,
# потому что проект у каждого окна свой.
loaded=$(cat "$slog/.loaded-count" 2>/dev/null)
shopt -s nullglob
extra=( "$HOME"/.claude/commands/*.md )
if [[ -n "$proj" && "$proj" != "$HOME" ]]; then
  extra+=( "$proj"/.claude/commands/*.md "$proj"/.claude/skills/*/SKILL.md )
fi
shopt -u nullglob
[[ -n "$loaded" ]] && loaded=$(( loaded + ${#extra[@]} ))

line2=""
nf=${#fired[@]}
if [[ -n "$loaded" ]] || (( nf > 0 )); then
  line2="${LBL}skills${RST} ${nf}"
  [[ -n "$loaded" ]] && line2+="/${loaded}"
  if (( nf > 0 )); then
    # последние пять, чтобы строка не разъезжалась; более ранние — счётчиком
    max=5
    shown=("${fired[@]:$(( nf > max ? nf - max : 0 ))}")
    names=""
    for s in "${shown[@]}"; do
      [[ -n "$names" ]] && names+="${LBL}, ${RST}"
      names+="$(fg "$C_SKILL")${s}${RST}"
    done
    (( nf > max )) && names="${LBL}+$(( nf - max ))${RST} ${names}"
    line2+="  ${names}"
  fi
fi

printf '%s' "$line1"
[[ -n "$line2" ]] && printf '\n%s' "$line2"
