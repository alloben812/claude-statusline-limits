# claude-statusline-limits

Статус-строка для [Claude Code](https://claude.com/claude-code) с **тратами токенов и лимитами подписки** прямо внизу окна:

```
Opus 4.8 1h 2m · $1.234 · ctx 42% · cache 1.5M · 5h 37% (2h 0m) · 7d 61% (3d 11h)
```

модель · длительность сессии · `$cost` · `ctx%` (цветом) · `cache` · **лимит 5 часов %** (до сброса) · **лимит 7 дней %** (до сброса).

Проценты 5-часового и недельного лимитов Claude Code отдаёт **нативно** в JSON статус-строки (`rate_limits.five_hour` / `seven_day`) — скрипт их только форматирует. Никаких внешних тулов (`ccusage` и т.п.) не нужно. Блок `5h/7d` показывается только на подписочном тарифе.

## Установка

Одной командой на любой машине:

```bash
curl -fsSL https://raw.githubusercontent.com/alloben812/claude-statusline-limits/main/install.sh | bash
```

Установщик:
- пишет `~/.claude/statusline-command.sh`;
- включает блок `statusLine` в `~/.claude/settings.json` (старый `settings.json` бэкапит в `settings.json.bak.<timestamp>`, остальные ключи не трогает).

Затем **перезапусти Claude Code** — строка появится внизу.

Из клона (без обращения к сети):

```bash
git clone https://github.com/alloben812/claude-statusline-limits
bash claude-statusline-limits/install.sh
```

**Зависимости:** `bash`, `jq` (`brew install jq` / `sudo apt install jq`). Работает на macOS и Linux.

## Что показывает

| Сегмент | Источник в JSON | Примечание |
|---|---|---|
| Модель + длительность | `model.display_name`, `cost.total_duration_ms` | |
| `$cost` | `cost.total_cost_usd` | стоимость сессии |
| `ctx%` | `context_window.used_percentage` | зелёный <50, жёлтый <80, красный ≥80 |
| `cache` | `context_window.current_usage.cache_*` | сумма read+creation |
| `5h %` | `rate_limits.five_hour` | % и время до сброса — только на подписке |
| `7d %` | `rate_limits.seven_day` | % и время до сброса — только на подписке |

## Скилл для Claude Code

В репозитории лежит скилл [`skills/statusline-limits/`](skills/statusline-limits/SKILL.md) — с ним Claude Code сам ставит, чинит и настраивает эту статус-строку по запросу («поставь статусную строку с лимитами», «статусбар не показывается»).

Подключить как пользовательский скилл (доступен во всех проектах):

```bash
git clone https://github.com/alloben812/claude-statusline-limits ~/claude-statusline-limits
ln -s ~/claude-statusline-limits/skills/statusline-limits ~/.claude/skills/statusline-limits
```

Или как проектный скилл — симлинк в `.claude/skills/` нужного проекта.

## Кастомизация

Правь `~/.claude/statusline-command.sh`:
- пороги цвета `ctx` — числа `50` / `80` в блоке *ctx с цветом*;
- убрать/добавить сегмент — строки `seg+=(...)` в блоке *собираем сегменты*;
- формат таймеров сброса — функция `fmt_left`.

Перезапуск после правки скрипта не нужен — он вызывается заново на каждом обновлении строки.

## Провенанс

Идея и раскладка — по мотивам внутреннего поста nodge (Яндекс, Этушка `post/4849970`, раздел 4).

## Лицензия

MIT — см. [LICENSE](LICENSE).
