# AGENTS.md — MindTree Adaptive Learning Engine

Продукт и архитектура описаны в `final_ai_learning_engine_refactoring_spec.md` (86 секций)
и `docs/`. Этот файл задаёт обязательные правила проекта и архитектурные инварианты, которые
должны соблюдать все агенты при работе в этом репозитории.

## Что такое MindTree

Пользователь указывает тему, цель и доступное время. Система строит минимально достаточный
путь к нужному уровню понимания, проводит через активную учебную сессию, проверяет результат
и предлагает следующий meaningful milestone. Ключевая метрика — `Learning Gain / Time`.
Циклы: `FAST UNDERSTANDING → CURRENT MASTERY → NEXT MILESTONE → DEEPER LEARNING`.

## Структура монорепо

- `mindtree_flutter/` — **приоритетное направление разработки**: автономный Flutter/Dart-клиент
  (drift/SQLite, свой LLM-клиент, свои промпты, Riverpod, go_router).
- `server/` — reference-стек: Node.js + Fastify + better-sqlite3 + Тип стек; зеркалит движок.
- `apps/{app,desktop,studio,web}/` + `packages/{graph,native,tauri-common,types,ui}/` — старое TS/React-окружение.
- `docs/`, `final_ai_learning_engine_refactoring_spec.md` — продуктовые спеки.
- `scripts/build-desktop.ps1` — сборка Tauri-десктопа.

## Главный инвариант: два параллельных стека

Движок и промпты **продублированы 1:1** между Flutter и TS-стеком:

- `mindtree_flutter/lib/data/prompts/prompts.dart` ↔ `server/src/prompts/*.ts` (17 билдеров).
- `mindtree_flutter/lib/domain/engines/*` ↔ `server/src/domain/*.ts` (17 engines).
- `mindtree_flutter/lib/providers/ui_stores.dart` ↔ `apps/web/src/stores/*`.

Правила:
1. Любая правка промпта или доменного движка меняется **синхронно в обоих стеках**, если
   иное явно не согласовано с пользователем.
2. `mindtree_flutter` — приоритет; `server/` — reference. При конфликте поведение согласуется
   с `final_ai_learning_engine_refactoring_spec.md` и существующими тестами.
3. При расхождении стеков — сначала выравнивай по приоритетному (flutter), затем зеркалируй.

## Инварианты дерева знаний

- Один корень на тему; `parentId` обязаны ссылаться на существующий узел; циклы запрещены.
- Состояния узла: `new → structureGenerated → expanded → validating → valid|invalid →
  repairing → contentGenerated → needsReview → failed` (см. `NodeState`).
- ID узлов — scoped-иды: `~`-суффикс + 8-hex hash (`lib/domain/engines/scoped_ids.dart`) —
  дедупликация id между темами. Не генерируй «голые» id.
- Лимиты контента: `one_liner` ≤ 120 символов; антижаргон обязателен для не-expert уровня.
- Промпты структурированных ответов возвращают JSON-контракты (`one_liner`, `details`,
  `analogy`, `relations`, `sequences`, ...). Никогда не «просто текстовый JSON» — валидация по схеме.

## LLM-конвенции

- Два тира моделей: `strong` (`structure, structure-l2, structure-l3, validate, repair,
  quiz, curriculum, diagnostic, assessment, mastery, tutor, milestone`) и `fast` (остальное).
- Поток LLM-вызовов через `TreeScheduler` (`lib/data/llm/scheduler.dart`): RPM/RPD-лимиты,
  retries, cooldown, контекст вызова. Не обходи scheduler напрямую без причины.
- Fallback обязателен: каждый AI-вызов имеет детерминированный запасной вариант
  (fallback-текст, эвристика, mock-режим). Сбой LLM не должен ронять пользовательский сценарий.
- Офлайн/mock: `LLM_MOCK`/`isMock` — детерминированные заглушки без слать запросов.
- Правки поведения движков не должны полагаться на «удачу модели» — контракты JSON валидируются.

## Домен обучения (детерминированная логика)

- Мастерство — 4 измерения: `understanding, recall, application, transfer`
  (`lib/domain/engines/learner_model_service.dart`).
- SRS-повторения — SM-2 (`lib/domain/lib/srs.dart`): interval 1→3→interval*ease, ease ±0.1
  (clamp 1.3–2.8), ошибка → сброс. Никакой случайности в reducer-логике.
- Мисконцепции отслеживаются отдельно и учитываются в промптах и выборе заданий.
- Та же детерминированная логика живёт в `server/src/domain/*.ts` (зеркало).

## Безопасность

- `mindtree_flutter/provider-config.json`, `server/.env*`, `server/data/runtime-config.json`
  содержат API-ключи. **Никогда** не коммитить, не логировать, не выводить в отчёт.
- Чувствительные данные в код/тесты не встраивать; использовать `tool/gen_config.ps1` и env.

## Команды валидации

- Flutter: `flutter analyze`, `flutter test`, кодогенерация `dart run build_runner build --delete-conflicting-outputs`.
- TS-стек: `npm run typecheck -w <pkg>`, `npm run lint`, `npm run test` (vitest), сборка `npm run build:all`.
- При правках всегда прогоняй соответствующие тесты (см. `.opencode/command/`).

## Конвенции реализации

- Именование и структура повториют существующую кодовую базу; баррели (напр. `models.dart`) — для экспортов.
- Для генерации кода (`*.g.dart`, freezed, riverpod) — build_runner, сгенерированные файлы коммитятся.
- UI-тексты и промпты — русский язык. Код-комментарии — русский, краткие.
- Windows/PowerShell: для цепочек команд используй `cmd1; if ($?) { cmd2 }` (нет `&&`).