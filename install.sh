#!/usr/bin/env bash
# Установщик statusline для Claude Code.
# Ставит ~/.claude/statusline-command.sh и включает блок statusLine в ~/.claude/settings.json.
#
# Установка на любой машине одной командой:
#   curl -fsSL https://raw.githubusercontent.com/alloben812/claude-statusline-limits/main/install.sh | bash
# Либо из клона репозитория:
#   git clone https://github.com/alloben812/claude-statusline-limits && bash claude-statusline-limits/install.sh
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SCRIPT="$CLAUDE_DIR/statusline-command.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
RAW="https://raw.githubusercontent.com/alloben812/claude-statusline-limits/main/statusline-command.sh"

mkdir -p "$CLAUDE_DIR"
command -v jq >/dev/null 2>&1 || { echo "✗ Нужен jq. macOS: brew install jq  |  Debian/Ubuntu: sudo apt install jq"; exit 1; }

# 1) скрипт статус-строки: из соседнего файла (если запущен из клона) либо из raw GitHub (если curl | bash)
if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ -f "$(dirname "${BASH_SOURCE[0]}")/statusline-command.sh" ]]; then
  cp "$(dirname "${BASH_SOURCE[0]}")/statusline-command.sh" "$SCRIPT"
  echo "✓ Скрипт скопирован из клона"
else
  curl -fsSL "$RAW" -o "$SCRIPT"
  echo "✓ Скрипт скачан из GitHub"
fi
chmod +x "$SCRIPT"
echo "✓ Записан $SCRIPT"

# 2) включаем statusLine в settings.json (создаём файл, если его нет; старый бэкапим рядом)
BLOCK='{"type":"command","command":"bash ~/.claude/statusline-command.sh"}'
if [[ -f "$SETTINGS" ]]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  tmp="$(mktemp)"
  jq --argjson b "$BLOCK" '.statusLine = $b' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
else
  jq -n --argjson b "$BLOCK" '{statusLine:$b}' > "$SETTINGS"
fi
echo "✓ statusLine включён в $SETTINGS"
echo "Готово. Перезапусти Claude Code — статус-строка появится внизу."
