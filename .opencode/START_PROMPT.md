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
>    4. @flutter-prompts — промпты (prompts.dart; server-зеркало заморожено)
>    5. @flutter-ui — экраны, graph, сторы ui_stores
>    6. @server — TS/Node reference (только по явной задаче; заморожен)
>    7. @testing — детерминированные тесты (домен, промпты, граф)
> 3. Источник истины — `mindtree_flutter`: `server/` заморожен, зеркалирование только по
>    явной просьбе пользователя; известные расхождения — `docs/server-mirror-known-divergence.md`.
> 4. Проверь результат (`flutter analyze`/`flutter test`, при правках server — `npm run typecheck/lint/test`).

---

## Вариант 2: продолжить с конкретного модуля

> @architect Продолжи реализацию MindTreeV2. Следующий модуль — [модуль, напр. pipeline L2/L3].
> Делегируй соответствующему subagent и проверь инварианты.

---

## Прямые вызовы конкретного агента

> @flutter-domain Реализуй [движок]. Соблюдай инварианты AGENTS.md и skill learning-domain.

> @flutter-data Добавь [таблицу/миграцию в drift]. Сгенерируй коды build_runner.

> @flutter-llm Подправь TreeScheduler/retry для [операции]. Учти тиры strong/fast и fallback.

> @flutter-prompts Измени [билдер промпта]. Следуй skill prompt-engineering (server-зеркало заморожено).

> @flutter-ui Реализуй [экран/виджет]. Свяжи с провайдерами ui_stores.

> @server Обнови [конкретный файл server/src/...] как зеркало принятого flutter-решения (только если просил пользователь).

> @product-reviewer Оцени готовность по §80 спеки (`/readiness`) или пройди UX-флоу (`/ux-review`).

> @testing Напиши детерминированные тесты для [логики]. Без LLM в регрессиях (skill testing).

---

## Команды

- `/test-flutter` — flutter analyze + flutter test (mindtree_flutter)
- `/gen-flutter` — кодогенерация build_runner (drift/freezed/riverpod)
- `/test-server` — npm run typecheck + lint + test (vitest)
- `/readiness` — аудит готовности продукта по §80–84 спеки (product-reviewer)
- `/ux-review` — проход шести флоу глазами пользователя (product-reviewer)
- `/review` — ревью дерева/сессии (content-reviewer)

---

## Памятка

- Всегда стартуй с `@architect` для крупных задач — он сам разбивает и делегирует.
- Узкие задачи — напрямую конкретному агенту (`@flutter-domain`, `@flutter-data` и т.д.).
- `@testing` не может править код (edit: deny) — только расчёты и тесты. Так же
  `@product-reviewer` и `@content-reviewer` — только отчёты.
- Промпты и движки правятся в `mindtree_flutter`; `server/` заморожен — зеркало только по
  явной просьбе (AGENTS.md, 06.10.2026).
- После изменения конфига opencode нужно перезапустить.