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
- `server/` — reference-стек: Node.js + Fastify + better-sqlite3. Исторически зеркалил домен
  и промпты; **заморожен** (см. «Статус server» ниже). **UI-клиента у него больше нет**.
- `packages/types/` — общий тип-контракт TS-стеков, используется `server/` (19 импортов).
- `docs/`, `final_ai_learning_engine_refactoring_spec.md` — продуктовые спеки.

> **Удалено 28.09.2026:** `apps/{app,desktop,studio,web}/`, `packages/{graph,native,tauri-common,ui}/`,
> `scripts/build-desktop.ps1`, `server/build-sidecar.mjs`. Причина: TS/React-продукт дублировал
> `mindtree_flutter/` и не имел пользователей; синхронизация трёх стеков съедала ~1/3 коммитов.
> `docs/exam-prep-plan.md` помечен устаревшим (написан под удалённый web-стек, не реализован).

## Статус `server/` — замороженный reference (решение принято 06.10.2026)

`server/` больше не обслуживает ни одного клиента: единственный потребитель API (web/Tauri) удалён.
Решение «дожимать до паритета или удалить» **закрыто**: принят вариант «заморозить».

- **Новые фичи в `server/` не делаются.** Он нужен как эталон и как место, где независимо
  проявляются баги зеркала (история это подтверждает: синхронизация находила реальные
  дефекты — дубли плейсхолдеров в промптах, рассинхрон дедлайна scheduler).
- **Обязательного зеркалирования больше нет** (см. «Два стека» ниже). Зеркалится только
  баг-фикс критичной доменной/промптной логики — и только по явной просьбе пользователя.
- **Известное расхождение** с flutter задокументировано в `docs/server-mirror-known-divergence.md`
  (8 пунктов, не зеркалируется намеренно). Это норма, а не долг: сверяйся с этим доком,
  прежде чем доверять `server/` как актуальной картине поведения.
- Правка в Flutter, намеренно расходящаяся с `server/`, — допустима без оговорок в ответе.

## Два стека: приоритет и зеркалирование

Исторически движок и промпты были продублированы 1:1 между Flutter и TS-стеком:

- `mindtree_flutter/lib/data/prompts/prompts.dart` ↔ `server/src/prompts/*.ts` (18 билдеров).
- `mindtree_flutter/lib/domain/engines/*` ↔ `server/src/domain/*.ts` (17 engines).
- `mindtree_flutter/lib/domain/models/models.dart` ↔ `packages/types/src/*` (тип-контракт).
- UI-слой зеркала **удалён** — синхронизировать UI больше не с чем.

Правила (после заморозки `server/`, 06.10.2026):

1. **`mindtree_flutter` — единственный источник истины.** Правки промптов и доменных
   движков делаются в Flutter; `server/` сам не обязан следовать.
2. **Зеркалирование — только по явной просьбе пользователя** (обычно это баг-фикс учебного
   поведения, который должен жить и в эталоне). Тогда: выравнивание по flutter → зеркало →
   зелёные `npm run typecheck`, `npm run lint`, `npm run test`.
3. При конфликте поведение согласуется с `final_ai_learning_engine_refactoring_spec.md`
   и существующими тестами; расхождение со `server/` фиксируется в
   `docs/server-mirror-known-divergence.md`.
4. Если синк сделан не был — это больше не блокер: просто зафиксируй расхождение в ответе.

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
- Офлайн/mock: `LLM_MOCK`/`isMock` — детерминированные заглушки без сетевых запросов.
- Правки поведения движков не должны полагаться на «удачу модели» — контракты JSON валидируются.

## Домен обучения (детерминированная логика)

- Мастерство — 4 измерения: `understanding, recall, application, transfer`
  (`lib/domain/engines/learner_model_service.dart`).
- SRS-повторения — SM-2 (`lib/domain/lib/srs.dart`): interval 1→3→interval*ease, ease ±0.1
  (clamp 1.3–2.8), ошибка → сброс. Никакой случайности в reducer-логике.
- Мисконцепции отслеживаются отдельно и учитываются в промптах и выборе заданий.
- Та же детерминированная логика жила зеркалом в `server/src/domain/*.ts`; после заморозки
  `server/` (06.10.2026) расхождение со flutter — норма, список — в
  `docs/server-mirror-known-divergence.md`.

## Безопасность

- `mindtree_flutter/provider-config.json`, `server/.env*`, `server/data/runtime-config.json`
  содержат API-ключи. **Никогда** не коммитить, не логировать, не выводить в отчёт.
- Чувствительные данные в код/тесты не встраивать; использовать `tool/gen_config.ps1` и env.

## Инструмент проверки качества: probe

`mindtree_flutter/tool/probe/` — headless-прогон доменного ядра **без UI и без Riverpod**.
Правило: обвязка движков живёт в `lib/domain/engines/engine_factory.dart`
(`buildEngines({repo, llmConfig, scheduler})`) — её используют и приложение, и probe,
и `tool/e2e/llm_smoke_test.dart`. Дублировать ручную обвязку промптов нельзя: smoke-тест
должен проверять тот же граф, что и приложение.

```powershell
# детерминированно, без сети и без ключа
& C:\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\probe\bin\mindtree_probe.dart --mock --out build\probe
# живой прогон через провайдера (нужен provider-config.json)
& C:\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\probe\bin\mindtree_probe.dart --query "теорема остановки" --out build\probe-live
```

Прогон проходит весь цикл (`tree → content → curriculum → diagnostic → session/activity →
assessment → mastery → milestones`) и кладёт в `--out`:

- `report.md` — самодостаточный артефакт: дерево, контент всех узлов, план, диагностика,
  шаги activity, ответы и вердикты LLM, мисконцепции, mastery, таблица проверок.
  Именно его читает агент, чтобы оценить качество выданного материала.
- `report.json` — то же машинно; детерминирован (побайтово совпадает между прогонами).
- `run-stats.json` — wall-clock, счётчики вызовов; **не** детерминирован.

Автоматические проверки качества — `tool/probe/quality_checks.dart`:
`single_root`, `parent_exists`, `no_cycles`, `level_consistent`, `one_liner_max_len`,
`no_empty_content`, `no_duplicate_labels`, `jargon_free`, `question_wellformed`,
`recall_wellformed`, `apply_wellformed`, `no_duplicate_activity`, `goal_coverage`,
`content_coverage`. Exit code `1`, если есть проверки уровня `fail`.

**Обязательно** прогоняй probe в `--mock` после правки промптов, движков и
`quality_checks` — это дешёвый способ поймать регрессии в учебном материале без UI.

## Команды валидации

- Flutter: `flutter analyze`, `flutter test`, кодогенерация `dart run build_runner build --delete-conflicting-outputs`.
- Probe: команда выше, `--mock` достаточно; полный набор команд — `tool/probe/README.md`.
- TS-стек: `npm run typecheck`, `npm run lint`, `npm run test` (vitest), сборка `npm run build:all`.
- При правках всегда прогоняй соответствующие тесты (см. `.opencode/command/`).

## Конвенции реализации

- Именование и структура повториют существующую кодовую базу; баррели (напр. `models.dart`) — для экспортов.
- Для генерации кода (`*.g.dart`, freezed, riverpod) — build_runner, сгенерированные файлы коммитятся.
- UI-тексты и промпты — русский язык. Код-комментарии — русский, краткие.
- Windows/PowerShell: для цепочек команд используй `cmd1; if ($?) { cmd2 }` (нет `&&`).