# claude-statusline-limits

Статус-строка для [Claude Code](https://claude.com/claude-code) с **тратами токенов и лимитами подписки** прямо внизу окна:

```
Opus 5.5 (1M context)  my-project  ▇░░░░░░░░░░░░░ 9%  94k/1M  $1.28  2h12m  cache 92k  5h 4% 2h56m  7d 21% 5h56m
skills 2/74  stefania-wiki, statusline-limits
```

Первая строка: модель · папка · `ctx` полоской, в % и токенами · `$cost` · длительность сессии · `cache` · **лимит 5 часов** в % и время до сброса · **лимит 7 дней** в % и время до сброса. Вторая строка: `skills`, сколько скиллов сработало в сессии из скольких доступно, и их имена.

Полоска контекста окрашена градиентом по месту клетки: до половины зелёная, дальше жёлтая, оранжевая и к концу красная. Цифра процента берёт цвет последней закрашенной клетки, проценты лимитов 5h/7d красятся по той же шкале.

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
| Модель | `model.display_name` | жирным |
| Папка | `workspace.current_dir` | имя последней папки пути |
| `ctx` | `context_window.used_percentage`, `current_usage`, `context_window_size` | полоска, % и занято/размер окна (`94k/1M`) |
| `$cost` | `cost.total_cost_usd` | стоимость сессии |
| Длительность | `cost.total_duration_ms` | `2h12m` |
| `cache` | `context_window.current_usage.cache_*` | сумма read+creation |
| `5h` | `rate_limits.five_hour` | % и время до сброса; только на подписке |
| `7d` | `rate_limits.seven_day` | % и время до сброса; только на подписке |
| `skills` | `transcript_path`, файлы `~/.claude/skill-log/` | вторая строка: сработало/доступно и последние пять имён |

### Сегмент skills

Сработавшие скиллы строка находит в транскрипте сессии (`transcript_path`) по двум шаблонам: вызов инструмента `Skill` и загрузка скилла командой. Команда покрывает набранный `/имя` и скилл, который Claude Code подгрузил сам (например `workflow-authoring` перед запуском Workflow). Такое сообщение в транскрипте начинается с `<command-message>`; у встроенных `/model`, `/clear`, `/effort` порядок тегов обратный, поэтому они не считаются. grep по транскрипту в 10 МБ занимает около 12 мс.

Плагин `skill-tracker` дополняет картину. Его хук PostToolUse на `Skill` пишет имена в `~/.claude/skill-log/<session_id>.txt`, туда попадают и вызовы из субагентов с отдельным транскриптом. Хук SessionStart кладёт число скиллов из плагинов и личных скиллов в `~/.claude/skill-log/.loaded-count`, а строка добавляет к нему личные команды `~/.claude/commands/*.md` и проектные `.claude/commands/*.md`, `.claude/skills/*/SKILL.md`. Без плагина знаменателя нет: строка покажет только сработавшие скиллы, а если их нет, вторая строка не выводится.

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
- светлый фон терминала: `export STATUSLINE_THEME=light` (своя палитра под светлый фон);
- градиент полоски: массив `RAMP` (коды палитры 256; truecolor не используется, его не умеет Apple Terminal), число клеток равно длине массива;
- остальные цвета: переменные `C_*` рядом с `RAMP`, `C_TRACK` отвечает за штриховку пустой части;
- убрать/добавить сегмент: строки `seg+=(...)` в блоке *первая строка*;
- сколько имён скиллов показывать: `max` во второй строке;
- формат таймеров сброса: функция `fmt_left`.

Заполненная часть полоски рисуется фоном клеток: символы-блоки (`█`, `▌`) Apple Terminal рисует шрифтом, и они выходят ниже строки. Пустую часть рисует штриховка `░`.

Перезапуск после правки скрипта не нужен — он вызывается заново на каждом обновлении строки.

## Провенанс

Идея и раскладка — по мотивам внутреннего поста nodge (Яндекс, Этушка `post/4849970`, раздел 4).

## Лицензия

MIT — см. [LICENSE](LICENSE).
