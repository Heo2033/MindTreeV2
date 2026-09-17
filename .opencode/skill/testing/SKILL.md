---
name: testing
description: Используй когда нужно написать или спроектировать тесты MindTree: детерминированные доменные тесты (SRS/дерево/ETA/mastery), регрессии промптов, граф-лейаут/канвас, widget/router-тесты, e2e LLM smoke, vitest для server. Тесты детерминированы и без LLM в регрессиях.
---

# Testing — паттерны тестирования и evaluation

Используй при написании тестов для MindTree. Ключевое — детерминированность и покрытие
инвариантов из `AGENTS.md`.

## Flutter

- Запуск: `flutter test` (в `mindtree_flutter/`); анализ: `flutter analyze`.
- Существующая структура: `test/router_test.dart`, `test/scoped_ids_test.dart`,
  `test/widget_test.dart`, `test/data/prompts/prompts_test.dart`,
  `test/ui/graph/graph_layout_test.dart`, `test/ui/graph/graph_canvas_test.dart`.
- Доменные тесты — детерминированные, без LLM: SRS (`lib/domain/lib/srs.dart`)
  interval 1→3→interval*ease, ease ±0.1, ошибка → сброс; валидация дерева (один корень,
  parentId существуют, нет циклов); ETA (`computeEtaFrom`); mastery-скоринг.
- Промпты: запрещённые токены (`{{TOKEN}}`), обязательные секции, валидность контрактов.
- Граф: layout компакт/айлам, `compactW` 72–300; canvas — PathMetrics, pan/zoom,
  guard `if (metrics.isEmpty) return;` при `_paintArrow`.

## TypeScript (server)

- Запуск: `npm run test` (vitest, конфиг `server/vitest.config.ts`), `npm run typecheck`,
  `npm run lint`.
- Промпт-тесты: `server/src/prompts/__tests__/content.test.ts`, `structureStep.test.ts`.
- Зеркальность: если тесты проверяют общий контракт — покрывай оба стека
  (skill `mono-sync`).

## E2E / live

- `mindtree_flutter/tool/e2e/llm_smoke_test.dart` — live-генерация дерева через реальный LLM
  (in-memory drift, KnowledgeGraphEngine, TreeScheduler, скип без ключа). Запуск — только с
  явного согласия пользователя (нужен API-ключ).
- В CI — mock/детерминированные сценарии (`isMock`), никаких ключей в тестах.

## Правила

- Без LLM в регрессионных тестах движка; вход → ожидаемый выход.
- Секреты в тесты не встраивать; `LLM_MOCK`, фикстуры, `tool/gen_config.ps1`.
- Тестируй границы: `nodesNeedingContent`, dangling parentId, пустой metrics,
  пустой curriculum (totalItems<1), лимит one_liner 120.