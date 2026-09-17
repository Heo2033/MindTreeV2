# Настройка AI-агентов (opencode) для MindTreeV2

Дата: 2025-06-25
Статус: план/документация

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
  остальное — ask. Модель — OpenCode Go, small — Go flash.
- `.opencode/.gitignore` — защита от коммита настроек (node_modules, package.json м.п.).

### Агенты (`.opencode/agent/`)
| Агент | mode | model |
|---|---|---|
| `architect` | primary | go (Qwen) |
| `flutter-domain` | subagent | big-pickle (free) |
| `flutter-data` | subagent | go flash |
| `flutter-llm` | subagent | go flash |
| `flutter-prompts` | subagent | go (Qwen) |
| `flutter-ui` | subagent | go flash |
| `server` | subagent | go flash |
| `testing` | subagent | big-pickle (free), `permission: edit: deny` |

Модели: подписка OpenCode Go (`opencode-go/*`); фолбэк — free-модели
(`opencode/big-pickle`, `opencode/mimo-v2.5-free`).

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