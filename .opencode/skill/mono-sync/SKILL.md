---
name: mono-sync
description: Используй когда меняешь общую логику MindTree — промпты (prompts.dart ↔ server/src/prompts/*.ts), доменные движки (lib/domain/engines/* ↔ server/src/domain/*.ts), тип-контракт (models.dart ↔ packages/types/src/*). Карта зеркал, правило приоритета и режим заморозки server/.
---

# Mono-Sync — два стека после заморозки `server/`

Исторически промпты и движки были продублированы 1:1 между Flutter и TS-стеком.
Главный инвариант репозитория теперь — **`mindtree_flutter` единственный источник истины**
(см. `AGENTS.md`, «Статус `server/`», решение 06.10.2026).

## Правило

`server/` — **замороженный reference**: новых фич не делается, обязательного зеркалирования
нет. Зеркалится только баг-фикс критичной доменной/промптной логики — и только по явной
просьбе пользователя. Известные расхождения — `docs/server-mirror-known-divergence.md`;
это документированная норма, а не долг.

## Карта зеркал (историческая, для чтения эталона)

| Flutter (приоритет) | TS / Node (reference, заморожен) |
|---|---|
| `mindtree_flutter/lib/data/prompts/prompts.dart` (18 билдеров) | `server/src/prompts/*.ts` (18 файлов) |
| `mindtree_flutter/lib/domain/engines/*` (17 engines) | `server/src/domain/*.ts` |
| `mindtree_flutter/lib/data/llm/{client,scheduler,cache,telemetry}.dart` | `server/src/llm/{client,scheduler,cache,telemetry}.ts` |
| доменные контракты моделей (`models.dart`) | `packages/types/src/*` (тип-контракт TS) |
| ~~`ui_stores.dart`~~ | ~~`apps/web/src/stores/*`~~ — **удалено 28.09.2026**, UI не зеркалится |

## Чек-лист при правке

1. Определи, что меняешь: промпт / движок / сторе / модель.
2. Правь в **приоритетном** стеке (`mindtree_flutter`). Это нормальный путь — трогать
   `server/` не обязательно.
3. Зеркалирование — только если пользователь явно просит: выравнивай по flutter,
   воспроизводи поведение Dart-файла, затем прогоны
   `npm run typecheck`, `npm run lint`, `npm run test`.
4. После правки промпта/движка/контракта — прогони probe в mock-режиме
   (`dart run tool/probe/bin/mindtree_probe.dart --mock --out build/probe`) и прочитай
   `report.md`: он показывает качество выданного материала глазами пользователя.
5. Новое/закрытое расхождение со `server/` — зафиксируй в ответе; обнови
   `docs/server-mirror-known-divergence.md`, если менял именно зеркало.

## Исключения

- Правка `server/`/`packages/types` по явной просьбе пользователя — там источник истины
  flutter, но синк выполняется целиком (все три прогона TS зелёные).
- Правка только UI-слоя — зеркала не существует (`apps/web` удалён 28.09.2026).
- `server/` может иметь собственную инфраструктуру (Fastify-роуты, координаторы
  в `server/src/application/*`) — это не зеркалится, это reference-внешности.

## Не забывай

- Поведение при конфликте выравнивается по `final_ai_learning_engine_refactoring_spec.md`
  и существующим тестам.
- Лимиты контента и JSON-контракты заданы в flutter (`AGENTS.md`); эталон их отражает
  на момент заморозки.