---
name: mono-sync
description: Используй когда меняешь общую логику, затрагивающую два параллельных стека MindTree: промпты (prompts.dart ↔ server/src/prompts/*.ts), доменные движки (lib/domain/engines/* ↔ server/src/domain/*.ts), UI-сторы (ui_stores.dart ↔ apps/web/src/stores/*). Чек-лист синхронизации и правило приоритета.
---

# Mono-Sync — синхронизация двух стеков

Используй при любой правке общей логики MindTree. Это главный инвариант репозитория
(см. `AGENTS.md`).

## Правило

`mindtree_flutter` — приоритет. `server` — reference. Промпты и движки продублированы 1:1.

## Карта зеркал

| Flutter (приоритет) | TS / Node (reference) |
|---|---|
| `mindtree_flutter/lib/data/prompts/prompts.dart` (17 билдеров) | `server/src/prompts/*.ts` (17 файлов) |
| `mindtree_flutter/lib/domain/engines/*` (17 engines) | `server/src/domain/*.ts` |
| `mindtree_flutter/lib/providers/ui_stores.dart` | `apps/web/src/stores/*` |
| `mindtree_flutter/lib/data/llm/{client,scheduler,cache,telemetry}.dart` | `server/src/llm/{client,scheduler,cache,telemetry}.ts` |
| доменные контракты моделей (`models.dart`) | `packages/types/src/*` (тип-контракт TS) |

## Чек-лист при правке

1. Определи, что меняешь: промпт / движок / сторе / модель.
2. Измени в **приоритетном** стеке (`mindtree_flutter`) или в том, что требует задача.
3. Если изменение общей контрактной логики — продублируй в зеркале (1:1).
4. Прогони тесты обоих стеков:
   - Flutter: `flutter analyze` + `flutter test` (в `mindtree_flutter/`);
   - TS: `npm run typecheck`, `npm run lint`, `npm run test`.
5. Если синк невозможен сразу — отметь расхождение в ответе и согласуй с пользователем.

## Исключения

- Правка только UI-слоя одного стека (не общего контракта) — синк не требуется.
- Пользователь явно разрешил править один стек — зафиксируй это в ответе.
- `server/` может иметь собственную инфраструктуру (Fastify-роуты, sidecar, координаторы
  в `server/src/application/*`) — это не зеркалится, это reference-внешности.

## Не забывай

- Поведение при конфликте выравнивается по `final_ai_learning_engine_refactoring_spec.md`
  и существующим тестам.
- «Голые» id, лимиты контента и JSON-контракты одинаковы в обоих стеках.