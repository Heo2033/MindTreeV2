---
name: learning-domain
description: Используй когда нужно работать с детерминированной доменной логикой обучения: mastery (4 измерения), SRS/SM-2, мисконцепции, типы вопросов/assessments, curriculum, ETA, adaptive-решения в mindtree_flutter/server.
---

# Learning Domain — паттерны домена обучения

Используй при реализации/проверке доменной логики MindTree. Вся логика — детерминированная.

## Mastery (LearnerModelService)

- 4 измерения: `understanding, recall, application, transfer` (const объявлены в
  `lib/domain/engines/learner_model_service.dart`).
- `ConceptProfile`: 4 dimension-балла + `confidence` + `errors` (мисконцепции) + SRS-поля
  (interval/ease/due) + `masteryScore` (усреднение).
- Слабые концепты: `getWeakConcepts(topicId, {limit})`. Мисконцепции учитываются в
  промптах (tutor, quiz) и выборе заданий.

## SRS (SM-2)

`lib/domain/lib/srs.dart` → `scheduleReview(prev, quality)`:
- correct: interval 1 → 3 → `interval*ease`; `ease + 0.1` (clamp 1.3–2.8).
- incorrect/again: interval=0, `ease - 0.2` (clamp 1.3–2.8), reps=0.
- `isDue(state)`, `estimateMastery(state)` (`interval/21`, clamp 0..1).
- Никакой случайности; следующее повторение — от `dueAt` (ISO).

## Assessment / вопросы

- Типы вопросов (6): см. `lib/domain/models/assessment.dart` (`QuestionType`).
- Постоянные правила: `_noMetaRule` (не задавай мета-вопросы), `_alphabetRule`
  (не нумеруй ответы буквами алфавита) — применяй в assessment/quiz/diagnostic промптах.
- Мастерство-оценка: `mastery_engine.dart` — LLM с детерминированным `_heuristic` fallback.

## Curriculum / ETA / Adaptive

- `curriculum_engine.dart`: минимально достаточный путь из дерева к цели (спека §17–19).
- ETA: `adaptive_learning_engine.dart::computeEtaFrom(elapsed, completed, total, baseMinutes)`
  → `SessionEta` (min/max оставшихся минут, `PaceClass` faster/onTrack/slower). Без RNG.
- `nextStep(sessionId)` → `AdaptiveDecision`: приоритеты — dueReviews → слабые концепты →
  «study next» → final assessment (progress ≥ 0.85).

## Мисконцепции

- `MisconceptionType`/`Misconception` (модель `mastery.dart`); ведутся в learner model
  и попадают в контекст промптов и в выбор ревью.

## Синхронизация

`server/src/domain/*.ts` — историческое зеркало детерминированной логики, **заморожено**
(AGENTS.md, 06.10.2026): правки здесь не обязывают трогать `server/`; зеркалирование —
только по явной просьбе пользователя (skill `mono-sync`).