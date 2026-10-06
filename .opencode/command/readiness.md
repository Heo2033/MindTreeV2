---
description: Аудит готовности продукта MindTree к релизу/MVP по acceptance criteria спеки §80–84 + метрики probe/review. Вердикт ГОТОВ/НЕ ГОТОВ и топ блокеров.
agent: product-reviewer
---

Оцени готовность MindTree к релизу по спеке, глазами пользователя и владельца продукта.

Действуй по инструкции агента `product-reviewer`:

1. Детерминированная база: в `mindtree_flutter/`
   `dart run tool\probe\bin\mindtree_probe.dart --mock --out build\probe`, прочитать
   `build/probe/report.md`; при наличии свежих ревью — `build/review/review-*.md`.
2. Проверить каждый пункт §80 (`Start, Plan, Learn, Adapt, Verify, Continue`) по коду
   (`lib/router.dart`, `lib/ui/screens/*`, `lib/providers/ui_stores.dart`, движки) —
   статус `ok/partial/missing` с доказательством.
3. Принципы §81–84: пять UX-вопросов, evidence-based mastery (§82), learning gain under
   constraints (§83), user decides how far to go (§84), §79 (нет утечки терминов движка в UI).
4. Отчёт: **вердикт** `ГОТОВ / ГРАНИЧНО / НЕ ГОТОВ` (какой блок рушит первым) → топ-5
   блокеров → таблица §80 → пять вопросов §81 → fail/warn из probe → раздел
   «Предложения» (отдельно от аудита).

Не правь код и данные сам — только докладывай; правки инициируй через `architect`.
