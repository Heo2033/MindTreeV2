---
name: prompt-engineering
description: Используй когда нужно править или тестировать промпты MindTree: noMetaRule/alphabetRule, антижаргон, структурный JSON-вывод, тиры моделей strong/fast, JSON-репар, санитизация ввода, синк промптов flutter↔server.
---

# Prompt Engineering — паттерны промптов MindTree

Используй при изменении промптов (flutter `prompts.dart` и/или `server/src/prompts/*.ts`).
Промпт — единственный рычаг поведения LLM; изменение движков промптами запрещено.

## Общие правила

- `noMetaRule` — запрет мета-вопросов («объясни концепцию X», «перескажи своими словами»).
- `alphabetRule` — не нумеровать варианты ответа буквами алфавита (a/b/c), только цифры.
- Императивный, однозначный стиль; язык — русский.
- Пользовательский ввод санита́рится: `_sanitizeUserQuery`/`_sanitizeTopic` — не позволяй
  инъекции ломать структуру промпта. Вставку всегда экранируй/цитируй.

## Структурированный вывод

- Контракты JSON: `one_liner`, `details`, `analogy`, `relations`, `sequences`, `claims`,
  `sources` и т.п. Каждый контракт описан в промпте явно и валидируется в движке
  (`parseLLMJson` в `client.dart`). Никогда не «просто попроси JSON».
- Валидация после модели обязательна; при невалидном JSON — ограниченный retry, затем
  детерминированный fallback (без бесконечных repair-циклов).

## Лимиты и уровни

- `one_liner` ≤ 120 символов; антижаргон обязателен для не-expert (`buildAudienceBlock`,
  `_antiJargonRule`).
- Глубина/время: `depthHintFor`, `timeHintFor` — подставляй в промпты генерации.
- `noMetaRule`/`alphabetRule` делегируются на assessment/quiz/diagnostic промпты.

## Тиры моделей

- `strong` (structure, structure-l2, structure-l3, validate, repair, quiz, curriculum,
  diagnostic, assessment, mastery, tutor, milestone) и `fast` (остальное).
  В промпте тир не задаётся — маршрутизация в `TreeScheduler`/`tierForOperation`.

## JSON-репар паттерны

- `parseLLMJson`: сначала прямой `jsonDecode`, затем code-fence extraction,
  затем bracket matching; control chars выводится через `_repairControlChars`.
- Для длинных ответов — извлечение первого `{...}`/`[...]` блока.

## Тестирование промптов

- Регрессия `{{TOKEN}}` и обязательных секций: `mindtree_flutter/test/data/prompts/prompts_test.dart`
  и `server/src/prompts/__tests__/*.test.ts`.

## Синхронизация

Промпты дублируются 1:1: `mindtree_flutter/lib/data/prompts/prompts.dart` ↔
`server/src/prompts/*.ts` (18 билдеров). Правка только одного стека — только с явного
согласия пользователя (skill `mono-sync`).