# Стартовый промпт для реализации MindTreeV2 (адаптивный обучающий движок)

Скопируй подходящий текст в новую сессию opencode. Все настройки агентов уже в `.opencode/`.

---

## Вариант 1 (рекомендуемый): полный запуск

> @architect Начни работу над MindTreeV2 (адаптивный обучающий движок).
> Соблюдай архитектурные инварианты из AGENTS.md и спеки
> `final_ai_learning_engine_refactoring_spec.md`.
>
> Шаги:
> 1. Ознакомься с AGENTS.md и структурой монорепо (mindtree_flutter — приоритет, server — reference).
> 2. Спланируй задачу и делегируй соответствующим subagents в порядке зависимостей:
>    1. @flutter-domain — доменные движки/модели дерева знаний
>    2. @flutter-data — drift-схема, mappers, repository
>    3. @flutter-llm — TreeScheduler, client, cache, telemetry, config
>    4. @flutter-prompts — промпты (prompts.dart ↔ server/src/prompts/*.ts)
>    5. @flutter-ui — экраны, graph, сторы ui_stores
>    6. @server — TS/Node reference (prompts/domain/llm зеркала, роуты)
>    7. @testing — детерминированные тесты (домен, промпты, граф)
> 3. Следи за инвариантом «два параллельных стека»: промпты и движки 1:1 в flutter и server.
> 4. Проверь результат (`flutter analyze`/`flutter test`, `npm run typecheck/lint/test`).

---

## Вариант 2: продолжить с конкретного модуля

> @architect Продолжи реализацию MindTreeV2. Следующий модуль — [модуль, напр. pipeline L2/L3].
> Делегируй соответствующему subagent и проверь инварианты.

---

## Прямые вызовы конкретного агента

> @flutter-domain Реализуй [движок]. Соблюдай инварианты AGENTS.md и skill learning-domain.

> @flutter-data Добавь [таблицу/миграцию в drift]. Сгенерируй коды build_runner.

> @flutter-llm Подправь TreeScheduler/retry для [операции]. Учти тиры strong/fast и fallback.

> @flutter-prompts Измени [билдер промпта] и его зеркало server/src/prompts/*. Следуй skill prompt-engineering.

> @flutter-ui Реализуй [экран/виджет]. Свяжи с провайдерами ui_stores.

> @server Обнови TS-зеркала промптов/движков и роуты API по packages/types.

> @testing Напиши детерминированные тесты для [логики]. Без LLM в регрессиях (skill testing).

---

## Команды

- `/test-flutter` — flutter analyze + flutter test (mindtree_flutter)
- `/gen-flutter` — кодогенерация build_runner (drift/freezed/riverpod)
- `/test-server` — npm run typecheck + lint + test (vitest)

---

## Памятка

- Всегда стартуй с `@architect` для крупных задач — он сам разбивает и делегирует.
- Узкие задачи — напрямую конкретному агенту (`@flutter-domain`, `@flutter-data` и т.д.).
- `@testing` не может править код (edit: deny) — только расчёты и тесты.
- Промпты и движки меняются синхронно в обоих стеках (flutter ↔ server), иначе расхождение фиксируется.
- После изменения конфига opencode нужно перезапустить.