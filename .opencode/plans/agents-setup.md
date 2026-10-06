# Настройка AI-агентов (opencode) для MindTreeV2

Дата: 2025-06-25
Статус: план/документация

> **Обновлено 06.10.2026** (документ ниже — история настройки; действующие правила — в
> `AGENTS.md`):
> - Принят вариант «заморозить `server/`»: обязательного зеркалирования стеков больше нет,
>   известные расхождения — `docs/server-mirror-known-divergence.md`. Формулировки
>   «инвариант двух стеков 1:1» и «синк с server/» ниже читай как исторические.
> - Добавлен агент `product-reviewer` (read-only) и команды `/readiness`, `/ux-review` —
>   аудит готовности и UX по §80–84 спеки. Также появился `/review` (content-reviewer).
> - Таблица агентов ниже неполна (см. `.opencode/agent/`), модели free-ротируются —
>   актуальные id смотри в самих файлах агентов.

## Цель

Настроить агентов opencode для монорепо MindTreeV2 так же хорошо, как это сделано
в `C:\home\projects\DnDMaster`. Приоритетное направление — `mindtree_flutter`
(автономный Flutter/Dart-клиент). `server/` — reference TS/Node-стек.

## Что создано

### Корневые файлы
- `AGENTS.md` — обязательные правила и инварианты проекта (два параллельных стека,
  дерево знаний, LLM-конвенции, домен, безопасность, команды валидации).
- `.opencode/opencode.json` — `default_agent: architect`; `instructions: ["AGENTS.md"]`;
  `skills.paths: [".opencode/skill"]`; permission bash: allow `flutter/dart/npm/node/git`,
  остальное — ask. Модель — `opencode/big-pickle` (free).
- `.opencode/.gitignore` — защита от коммита настроек (node_modules, package.json м.п.).

### Агенты (`.opencode/agent/`)
| Агент | mode | model | почему |
|---|---|---|---|
| `architect` | primary | big-pickle | держит инварианты и зеркальность стеков |
| `flutter-domain` | subagent | big-pickle | детерминированная логика (SRS, mastery), ошибки не видны в UI |
| `flutter-prompts` | subagent | big-pickle | контракты промптов и их синк с `server/` |
| `flutter-llm` | subagent | big-pickle | лимиты, retry, fallback — цена ошибки высока |
| `flutter-data` | subagent | big-pickle | drift-миграции: ошибка компилируется и проходит тесты на чистой БД, но портит существующую |
| `testing` | subagent | big-pickle | `permission: edit: deny`, проектирует тесты |
| `content-reviewer` | subagent | big-pickle | ловит тонкие дефекты материала; слабая модель = ложная уверенность |
| `flutter-ui` | subagent | mimo-v2.6-flash-free | нужна UX-оценка, но гейт — `flutter analyze` + widget-тесты |
| `server` | subagent | fledge-alpha-free | зеркалирование принятого Dart-решения, гейт жёсткий: `tsc` + `eslint` + `vitest` |

Модели: все агенты на бесплатном провайдере `opencode`.
Модели OpenCode Go (`opencode-go/*`) отключены не из-за имён — по разбору
`~/.local/share/opencode/log/opencode.log` (147 строк ERROR) причина в четырёх
независимых вещах:

| Модель | Ошибка | Сколько | Что это |
|---|---|---|---|
| `deepseek-v4-flash` | `This Go model requires Global regions` | 120 | **настройка приватности workspace**, не лимит и не имя |
| `deepseek-v4-flash` | `only available hosted in China and requires explicit opt in` | 3 | региональный гейт |
| `qwen3.6-plus` | `data_inspection_failed <400> InternalError.Algo.DataInspection` | 15 | провайдер отклоняет часть запросов; последняя — 02.10.2026 |
| `qwen3.6-plus` | `Weekly usage limit reached. Resets in 2-3 days` | 3 | квота |
| `qwen3.8-max` | `5-hour usage limit reached` | 3 | квота |
| `qwen3.7-plus` | `No payment method` | 2 | нет оплаты |
| `qwen3.8-max` | `Endpoint is unavailable` | 1 | транзиентный обрыв провайдера |

Имена у моделей валидные: `qwen3.6-plus` сделала 428 успешных stream-вызовов
(последний 24.09.2026), `deepseek-v4-flash` — рабочие вызовы 02.10.2026. То есть
Go-модели вернутся, если выставить workspace в Global-регион; сейчас блокирует
именно региональная настройка, а не лимит.

Операционные факты (проверены 02.10.2026):

- **Конфиг агентов читается при старте opencode.** Правка `model:` в
  `.opencode/agent/*.md` не подхватывается в уже запущенном процессе: проба
  агента после правки всё ещё уходила на старое имя модели. Каждая правка
  требует рестарта opencode — отсюда проверять модели по одной нельзя,
  только пачкой за один перезапуск.
- **Free-модели ротируются.** `opencode/mimo-v2.5-free` и
  `opencode/deepseek-v4-flash-free` проработали на этой машине (234 и 35
  сообщений), но к 02.10.2026 уже отсутствуют в каталоге провайдера; вместо них
  доступны `mimo-v2.6-flash-free`, `ling-3.0-flash-fin-free`, `fledge-alpha-free`.
  При ошибке `Model not found` нужно обновить id в этом файле (opencode сам
  печатает список актуальных имён в подсказке) и перезапустить opencode.
- По этой же причине `big-pickle` стоит на всех агентах, где цена ошибки
  высокая: он единственный проверен в текущем прогоне (27k сообщений) и не
  исчезает при ротации free-каталога.

### Скиллы (`.opencode/skill/`)
- `tree-generation` — пайплайн L1/L2/L3, expand/validate/repair/content, NodeState,
  scoped ids, лимиты.
- `learning-domain` — mastery (4 измерения), SRS/SM-2, мисконцепции, ETA, curriculum.
- `prompt-engineering` — noMeta/alphabet, антижаргон, JSON-контракты, тиры моделей,
  JSON repair, санитизация.
- `llm-pipeline` — TreeScheduler (RPM/RPD/retries), client (OpenAI/Ollama/SSE),
  cache, telemetry, provider config, mock/офлайн.
- `mono-sync` — синхронизация двух стеков (промпты/движки/сторы).
- `testing` — детерминированные тесты, регрессии промптов, граф, e2e.

### Команды (`.opencode/command/`)
- `/test-flutter` — `flutter analyze` + `flutter test`.
- `/gen-flutter` — `dart run build_runner build --delete-conflicting-outputs`.
- `/test-server` — `npm run typecheck` + `npm run lint` + `npm run test` (vitest).

### Документация
- `START_PROMPT.md` — стартовая инструкция для сессии opencode.
- `plans/agents-setup.md` — этот документ.

## Ключевые решения и правила

- Конфиг размещён в корне MindTreeV2 (opencode ищет walk-up от cwd).
- Главный инвариант — «два параллельных стека» 1:1; flutter — приоритет, server —
  reference; при расхождении сначала правится flutter.
- Домен детерминирован; LLM-вызовы только через TreeScheduler с fallback.
- Секреты: `provider-config.json`, `server/.env*`, `runtime-config.json` — не коммитить,
  не логировать.
- Windows/PowerShell: цепочки `cmd1; if ($?) { cmd2 }`.

## Дальнейшие шаги (checklist)
- [x] AGENTS.md, opencode.json, .gitignore
- [x] 8 агентов
- [x] 6 скиллов
- [x] 3 команды
- [x] START_PROMPT.md, plans/agents-setup.md
- [ ] Валидация: проверить, что opencode стартует без ConfigInvalidError; подтвердить
      модель `/models` после reauth; перезапустить opencode (конфиг не hot-reload).