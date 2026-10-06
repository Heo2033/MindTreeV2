# Известное расхождение `server/` с flutter (не зеркалируется)

Исторический чек-лист отложенного зеркалирования. **Статус: расхождение зафиксировано
06.10.2026 и намеренно не зеркалируется** — `server/` заморожен как reference без
обязательного синка (решение: вариант «заморозить», см. `AGENTS.md`, раздел
«Статус `server/`»). Этот док — память о том, чем `server/` отличается от flutter,
а не задание к выполнению.

Источник истины при конфликте — **flutter**. Пока `server/` не обслуживает клиента,
поведение ниже намеренно расходится: новые фичи и изменения учебного поведения живут
только в `mindtree_flutter/`.

## Что уже зеркалировано вручную (до заморозки)

| Правка | Файл |
|---|---|
| Мисконцепция `careless` пишется только при `quality === 'incorrect'`, а не при любом не-`correct` (ранее `'again'` создавал ложную запись) | `server/src/domain/ReviewScheduler.ts` |
| Восстановлены экспорты `buildAssessmentPrompt`, `parseAssessmentResult`, `AssessmentQuestionResult`, исправлена кириллица тела промпта, `Math.random()` → `shortIdWith("q_")`, резолв `correctAnswer` через `resolveCorrectAnswerIndex`, отбрасывание непроверяемых вариантов вопроса | `server/src/prompts/assessment.ts` |

## Известное расхождение (есть в flutter, нет в server)

| # | Что меняется | Flutter | Server |
|---|---|---|---|
| 1 | `onAnswered` получает опциональные `evidence` (карта измерений) и `recordCareless`; **убран двойной рост** (`+0.15 recall / +0.1 understanding` больше не добавляются поверх бленда) — теперь только SRS + `recordEvidence`; по умолчанию пишется только `recall` со score 1/0 | `lib/domain/engines/review_scheduler.dart` | `server/src/domain/ReviewScheduler.ts` |
| 2 | Признак «не оценено»: отказ LLM и `partial` **не** трогают модель, **не** сбрасывают SRS и **не** пишут `careless`, но `feedback` обязателен через `heuristicApplyFeedback`; введены `kQualityUnevaluated` и `AnswerFeedback.evaluated`; санитизация через общую `sanitizeFeedbackResult`, локальные `_sanitize*` удалены | `lib/domain/engines/feedback_engine.dart` | `server/src/domain/FeedbackEngine.ts` |
| 3 | Единое накопление `recordEvidence` (`new = prev*(1-0.5) + score*0.5`, `kEvidenceWeight = 0.5`), `kUnmeasuredDimension = 0.0`, монотонный `raiseOverallLevel` (`asInitial` фиксирует старт один раз) | `lib/domain/engines/learner_model_service.dart` | `server/src/domain/LearnerModelService.ts` |
| 4 | **Убран хардкод** `understanding/recall=0.6, application=0.4, transfer=0.3` всем «известным» концептам после диагностики; вместо него `recordEvidence` по каждому реальному ответу | `lib/domain/engines/diagnostic_engine.dart:225-232` | `server/src/domain/DiagnosticEngine.ts` |
| 5 | Абсолютная перезапись 4 измерений на `recordEvidence`; пустое описание мисконцепции не пишется (известный тип → `defaultDescription`, `unknown`/пусто → скип) | `lib/domain/engines/mastery_engine.dart` | `server/src/domain/MasteryEngine.ts` |
| 6 | `markItemCompleted`: качество выводится из результатов шагов активности, не хардкод `'correct'`; `evidence: {}` («закрыть концепт» — не ответ) | `lib/domain/engines/learning_session_engine.dart`, `lib/domain/lib/activity_blob.dart` | `server/src/domain/LearningSessionEngine.ts` |
| 7 | `LearningActivityService` получает `FeedbackEngine`, приватные `_evaluateRecall`/`_evaluateApply` удалены; событие `activity_answer` несёт `evaluated`/`score` | `lib/domain/engines/learning_activity_service.dart` | `server/src/domain/LearningActivityService.ts` |
| 8 | Тип-контракт: `AnswerFeedback.evaluated`, quality-литералы, `MisconceptionType.defaultDescription` | `lib/domain/models/mastery.dart` | `packages/types/src/mastery.ts`, `packages/types/src/learning.ts` |

## Если зеркалирование всё же понадобится (по явной просьбе)

1. Прочитать эквивалентный Dart-файл и воспроизвести поведение, а не приблизительно
   переписывать TypeScript.
2. `npm run typecheck`, `npm run lint`, `npm run test` — все три зелёные.
3. Сверить с flutter-тестами: `test/domain/activity_feedback_learning_test.dart`,
   `test/domain/diagnostic_mastery_incremental_test.dart`,
   `test/domain/mark_item_completed_quality_test.dart`,
   `test/domain/completion_quality_test.dart`.

## Открытые вопросы (косметические, не влияют на приоритетный стек)

- `partial` возвращает `AnswerFeedback.quality == 'incorrect'`, хотя для SRS он нейтрален
  (correct=false, score=0.5, evaluated=true). Косметика, не влияет на модель, но логичнее
  отдельное качество `'partial'`.
- `updateMisconception` в learner model всё ещё сохранит пустой `description`, если вызвать
  напрямую; движки им больше так не пользуются, но путь существует.
