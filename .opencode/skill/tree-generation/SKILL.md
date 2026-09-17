---
name: tree-generation
description: Используй когда нужно реализовать, отладить или изменить генерацию дерева знаний: пайплайн L1/L2/L3, expand, validate, repair, content, NodeState-машина, scoped ids, лимиты one_liner, валидация дерева в mindtree_flutter/server.
---

# Tree Generation — паттерны генерации дерева знаний

Используй при работе с генерацией дерева знаний MindTree в обоих стеках.

## Пайплайн (KnowledgeGraphEngine)

`L1 (обзор/корень) → L2 (ключевые узлы) → L3 (листья) → expand → validate → repair → content`.

- `buildL1Prompt` → корень темы (обзор). `buildL2Prompt`/`buildL3Prompt` — уровни по
  parent-context. `buildExpandPrompt` — расширение по требованию. `buildValidatePrompt` /
  `buildRepairPrompt` — цикл контроля качества. `buildContentPrompt` — наполнение контента.
- Промпт-маппинг движка: `mindtree_flutter/lib/providers/app_providers.dart`
  (`knowledgeGraphEngineProvider` — связаны билдеры и вызовы).

## NodeState-машина

`new → structureGenerated → expanded → validating → valid|invalid → repairing →
contentGenerated → needsReview → failed` (`lib/domain/models/knowledge_node.dart`).
Любой переход — осмысленный: не ставь `contentGenerated` до заполнения контента, не
возвращай узел из `failed` в `new_` без причины.

## Структура узла (JSON-контракт)

- `id` — scoped: `{base_id}~{8-hex}` через `lib/domain/engines/scoped_ids.dart`.
  Никогда «голые» id — дедупликация между темами.
- `label`, `one_liner` (≤120 символов), `details`, `analogy` (nullable), `sources`,
  `conceptType`, `importance`, `difficulty`, `estimatedTimeMinutes`, `state`,
  `contentLoaded`, `leaf`, `relations`, `sequences`.

## Инварианты дерева

- Один корень на тему; `parentId` ссылаются на существующий узел; циклы запрещены.
  Проверка: `lib/domain/lib/tree_validation.dart`.
- Порядок обхода: `lib/domain/lib/tree_reading.dart` (readingOrder — DFS, buildToc,
  branchProgress).
- Содержимое: один корень; листья и ветви генерируются в нужном порядке
  (L1→L2→L3, затем контент) — см. `nodesNeedingContent` в `mindtree_repository.dart`.

## Лимиты и антижаргон

- `one_liner` ≤ 120 символов; для не-expert — антижаргон (блоки `_antiJargonRule`).
- Инструкции промпта — на русском, JSON-контракт явный; выдуманные `sources` запрещены.
- Для корня/обзора аккуратно с `_rootGuidance`, `_twoPartDetailsBlock`, `_rootFormulaBan`.
- Идея «двухэтапного one_liner» (docs/idea-one-liner-two-stage-root.md) — отложена,
  без согласования не делать.

## Синхронизация

Любая правка промпта/движка дерева — в обоих стеках (flutter ↔ `server/src/prompts/*.ts`,
`server/src/domain/*.ts`). См. skill `mono-sync`.