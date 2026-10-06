---
description: Прогнать проверки TS/Node-стека: npm run lint, npm run typecheck, npm run test (vitest). Для server и затронутых пакетов.
agent: server
---

Запусти проверки TypeScript/Node-стека MindTree и сообщи результат. Выполняй из корня
монорепо `C:\home\projects\MindTreeV2`.

Команды (последовательно, чтобы ранняя остановка указывала на проблему):
1. `npm run typecheck` — проверка типов всех workspaces
2. `npm run lint` — ESLint (`packages/types/ server/src/`)
3. `npm run test` — vitest (конфиг `server/vitest.config.ts`); можно передать
   `npm run test -- $ARGUMENTS` для фильтра.

Ожидания:
- typecheck и lint без ошибок.
- Тесты зелёные, включая промпт-тесты (`server/src/prompts/__tests__/`).

Особое внимание: `server/` заморожен (AGENTS.md, 06.10.2026) — зеркальность с
`mindtree_flutter` не проверяется «на всякий случай»; только если зеркалирование
просил пользователь (skill `mono-sync`).