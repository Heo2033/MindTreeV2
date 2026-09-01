# AI Learning Engine — финальная спецификация рефакторинга

## 1. Назначение документа

Этот документ описывает целевую продуктовую концепцию и архитектурные направления для рефакторинга существующего приложения.

Важно: продукт **не должен превращаться в обычную LMS, генератор курсов или просто красивый knowledge graph**.

Основная идея:

> **Пользователь указывает тему, цель и доступное время. Система определяет минимальный достаточный путь к нужному уровню понимания, проводит пользователя через активную учебную сессию, проверяет результат и предлагает следующий meaningful milestone, если пользователь хочет углубиться.**

Таким образом продукт состоит из двух связанных циклов:

```text
FAST UNDERSTANDING
        ↓
CURRENT MASTERY
        ↓
NEXT MILESTONE
        ↓
DEEPER LEARNING
        ↓
NEW MASTERY
        ↓
NEXT MILESTONE
        ↓
...
```

Пользователь никогда не обязан изучать всю тему.

---

# 2. Главная продуктовая философия

## Не:

> «Изучить всю тему».

## Не:

> «Пройти сгенерированный курс».

## Не:

> «Прочитать все листья дерева».

## А:

> **«Достичь нужного уровня понимания с минимально необходимыми затратами времени и продолжить углубление только при необходимости».**

Ключевая метрика:

```text
Learning Gain / Time
```

Продукт должен оптимизировать не количество просмотренного контента, а реальное изменение знаний и способности применять их.

---

# 3. Главная единица продукта — Learning Journey

Систему нужно мыслить не как один курс.

У пользователя есть:

```text
Topic
Goal
Current Mastery
Target Mastery
Learning History
```

А внутри темы существует последовательность milestones.

Например:

```text
Diffusion Models

Awareness
    ↓
Basic Understanding
    ↓
Solid Understanding
    ↓
Practical Application
    ↓
Implementation
    ↓
Advanced Theory
    ↓
Research
```

Пользователь может остановиться на любом этапе.

Если его цель достигнута:

```text
ENOUGH
```

Если хочет глубже:

```text
CONTINUE
```

---

# 4. Learning Session

Каждый отдельный учебный заход является `LearningSession`.

Пример:

```text
Topic:
Diffusion Models

Goal:
Understand

Current level:
Beginner

Target:
Solid Understanding

Time budget:
2 hours

Session result:
Solid Understanding
```

Следующая сессия:

```text
Topic:
Diffusion Models

Goal:
Practical Application

Current level:
Solid Understanding

Target:
Practical Application

Time budget:
3 hours
```

Это позволяет одному topic развиваться постепенно, а не создавать новый независимый курс каждый раз.

---

# 5. Пользовательский flow

Целевой flow:

```text
1. Enter topic
        ↓
2. Define goal
        ↓
3. Choose available time
        ↓
4. Diagnostic
        ↓
5. Generate / load knowledge graph
        ↓
6. Determine current mastery
        ↓
7. Determine target milestone
        ↓
8. Generate minimum sufficient curriculum
        ↓
9. Start learning session
        ↓
10. Explain
        ↓
11. Recall
        ↓
12. Apply
        ↓
13. Adaptive feedback
        ↓
14. Final assessment
        ↓
15. Update mastery
        ↓
16. Show achieved level
        ↓
17. Recommend next milestone
```

---

# 6. Topic не должен быть равен курсу

Например:

```text
Diffusion Models
```

может занимать:

```text
15 min
30 min
1 hour
2 hours
5 hours
20+ hours
```

в зависимости от цели.

Поэтому приложение должно поддерживать **разную глубину одной темы**.

---

# 7. Learning Depth

Уровни не должны быть универсальной жёсткой шкалой для всех предметов.

Но базовую модель можно использовать:

```text
Level 0 — Awareness
Level 1 — Basic Understanding
Level 2 — Solid Understanding
Level 3 — Practical Application
Level 4 — Advanced
Level 5 — Expert / Research
```

Для конкретной области AI может генерировать более подходящие названия.

Например, программирование:

```text
Understand
Use
Build
Debug
Design
Master
```

Математика:

```text
Understand
Solve
Apply
Derive
Generalize
```

Важно:

> **Level — это не процент завершения дерева.**

Нельзя показывать:

```text
73% of Diffusion Models
```

как главный показатель.

Нужно показывать:

```text
Solid Understanding
```

и конкретные capabilities, которые этому соответствуют.

---

# 8. Capability-based mastery

Каждый milestone должен описываться через то, что пользователь реально способен делать.

Например:

## Solid Understanding — Diffusion Models

Пользователь может:

- объяснить основную идею;
- объяснить forward diffusion;
- объяснить reverse diffusion;
- объяснить роль noise prediction;
- объяснить базовую идею DDPM;
- описать sampling на концептуальном уровне.

Но пока не обязательно:

- реализовать DDPM;
- вывести математическую формулировку;
- разбираться во всех samplers;
- читать современные papers.

---

# 9. Next Milestone

После каждой значимой сессии система должна отвечать на вопрос:

> **«Что я могу получить, если продолжу обучение?»**

Пример:

```text
Current:
Solid Understanding

Next:
Practical Application

Estimated effort:
~3–5 hours

After this you will be able to:
- use diffusion models;
- understand inference parameters;
- reason about sampling;
- solve common practical problems.
```

Затем альтернативные направления:

```text
Implementation       ~6–10h
Advanced Theory      ~8–15h
Research             ~20h+
```

Это должно быть визуализировано как learning roadmap.

---

# 10. Не делать путь линейным

Пользователь может выбирать направление.

Например:

```text
                  Solid Understanding
                          │
            ┌─────────────┼──────────────┐
            ↓             ↓              ↓
       Application      Theory        Research
            │             │              │
            ↓             ↓              ↓
      Implementation     SDE           Papers
```

Приложение должно объяснять:

> Почему этот путь подходит.

---

# 11. «Enough» — полноценный результат

Если пользователь достиг своей цели, система должна уметь сказать:

> **Тебе, вероятно, не нужно изучать дальше для этой цели.**

Например:

```text
Goal:
Understand diffusion models for product discussions

Current:
Solid Understanding

Recommendation:
STOP / ENOUGH
```

Не нужно искусственно создавать дополнительные этапы ради retention.

Это принципиально важно для доверия.

---

# 12. Goal-driven learning

Одна тема должна строить разные trajectories в зависимости от цели.

Например:

## Diffusion Models — Understand

Фокус:

```text
Core intuition
Forward process
Reverse process
DDPM
Sampling
Conditioning
```

## Diffusion Models — Implement

Добавить:

```text
Math foundations
Noise schedule
Training objective
U-Net
Time embedding
Implementation
Debugging
```

## Diffusion Models — Research

Добавить:

```text
Score matching
SDE formulation
Advanced sampling
Latent diffusion
DiT
Flow matching
Papers
Research directions
```

Следовательно:

> **Curriculum зависит не только от topic, но и от goal.**

---

# 13. Time Budget

Пользователь должен задавать:

```text
15 min
30 min
1 hour
2 hours
4 hours
Custom
```

Система не должна просто растягивать текст.

При увеличении времени должны добавляться:

- prerequisites;
- nuance;
- application;
- edge cases;
- deeper mechanisms;
- implementation;
- transfer;
- advanced theory.

---

# 14. Minimum Sufficient Knowledge

Ключевой алгоритм:

> Из полного знания темы выбрать минимальный набор концепций, достаточный для достижения конкретной цели на конкретном уровне.

Пример:

```text
Full Graph
    ↓
Goal relevance
    ↓
Prerequisite analysis
    ↓
Importance
    ↓
Difficulty
    ↓
Estimated time
    ↓
Minimum sufficient curriculum
```

---

# 15. Just Enough Prerequisites

Нельзя позволять prerequisite graph уходить в бесконечность.

Например:

```text
Diffusion Models
 → Probability
 → Calculus
 → Linear Algebra
 → ...
```

Если для текущей цели достаточно 7-минутного объяснения Gaussian noise, не отправлять пользователя проходить полный Probability course.

Принцип:

> **Just enough prerequisite knowledge.**

---

# 16. Full Knowledge Graph

Knowledge graph остаётся важным внутренним объектом.

Но он не является обязательным curriculum.

Пример:

```text
Diffusion Models
├── Core idea
├── Forward diffusion
├── Reverse diffusion
├── DDPM
├── Score matching
├── SDE
├── U-Net
├── Time embedding
├── Sampling
├── Classifier guidance
├── CFG
├── Latent diffusion
├── Stable Diffusion
├── DiT
└── Flow matching
```

---

# 17. Session Curriculum

Из полного graph выбирается подмножество:

```text
2-hour session

Core idea
Forward diffusion
Reverse diffusion
DDPM
Noise prediction
Training objective
Sampling
Conditioning
Latent diffusion
Final assessment
```

Остальное:

```text
Optional
Deferred
Advanced
```

---

# 18. Session Planning

Перед началом показать:

```text
DIFFUSION MODELS
Solid Understanding
2 hours

10m  Core intuition
12m  Forward diffusion
15m  Reverse diffusion
20m  DDPM
15m  Training objective
10m  Sampling
08m  Conditioning
10m  Latent diffusion
10m  Final assessment

Total:
~1h 50m
```

Пользователь должен видеть:

- зачем изучается каждый блок;
- сколько времени займёт;
- какой результат ожидается.

---

# 19. Adaptive Curriculum

План не должен быть статичным.

Если пользователь быстро освоил блок:

```text
Expected:
20m

Actual:
10m
```

система может:

- сохранить время;
- углубить следующий важный блок;
- добавить application;
- закончить раньше.

Если пользователь испытывает трудности:

```text
Expected:
10m

User struggling
```

система может:

- изменить объяснение;
- дать аналогию;
- дать дополнительный пример;
- проверить prerequisite;
- вставить corrective exercise.

При дефиците времени система должна убирать второстепенный материал, а не просто увеличивать session duration.

---

# 20. Priority Model

Каждый concept должен иметь метаданные:

```text
importance
goal_relevance
prerequisite_value
difficulty
estimated_time
```

Curriculum Engine должен выбирать знания с высокой полезностью на единицу времени.

Концептуально:

```text
priority =
goal relevance
× prerequisite value
× importance
÷ estimated time
```

Конкретная формула может быть другой.

Главное:

> **Оптимизировать learning gain per minute.**

---

# 21. Learning Loop

Каждый важный концепт должен проходить цикл:

```text
Explain
   ↓
Example
   ↓
Recall
   ↓
Apply
   ↓
Feedback
```

Не использовать модель:

```text
Read 30 pages
→ Next
→ Read 30 pages
```

---

# 22. Активное обучение

Рекомендуемая эвристика для концептуальной темы:

```text
20–35% explanation / examples
20–30% retrieval
30–40% application
10–20% synthesis / assessment
```

Для разных предметов распределение должно адаптироваться.

---

# 23. Assessment

Тесты — не отдельный декоративный feature.

Assessment должен быть встроен в learning loop.

Типы:

```text
Recognition
Recall
Explanation
Application
Diagnosis
Transfer
```

Не полагаться только на multiple choice.

---

# 24. Final Assessment

Финальная проверка должна отвечать:

> «Действительно ли пользователь достиг заявленного уровня?»

Минимум:

```text
Recall
+
Explanation
+
Application
```

Где возможно:

```text
+
Transfer
```

---

# 25. Synthesis

В конце полезно попросить пользователя сформировать mental model.

Например:

> Объясни Diffusion Models человеку, который знает neural networks, но никогда не изучал diffusion.

Или:

> Опиши путь от random noise до generated image.

AI должен анализировать:

- полноту;
- правильность;
- причинно-следственные связи;
- misconceptions;
- способность переносить знание.

---

# 26. Learner Model

Хранить состояние знания по concepts.

Минимальная модель:

```text
Concept
Mastery
Confidence
Errors
Misconceptions
Last assessed
```

Пример:

```text
Reverse diffusion

Understanding: 0.82
Application:   0.58

Misconception:
Confuses training and sampling
```

---

# 27. Misconception Model

Не все ошибки одинаковы.

Система должна различать:

```text
Unknown concept
Confused concepts
Incomplete mental model
Definition-only knowledge
Mechanism misunderstanding
Application failure
Careless error
```

После ошибки не просто говорить:

> Incorrect.

А определять причину и адаптировать обучение.

---

# 28. Mastery не должно быть одной цифрой

Не использовать только:

```text
Mastery = 73
```

Лучше иметь несколько измерений:

```text
Understanding
Recall
Application
Transfer
```

А UI переводит это в понятный milestone:

```text
Solid Understanding
```

---

# 29. Book Mode

Книга остаётся, но её роль меняется.

Она является:

> **structured explanation layer**

Структура:

```text
Chapter
 ↓
Concept
 ↓
Explanation
 ↓
Example
 ↓
Quick check
```

Оглавление справа сохраняется.

---

# 30. Knowledge Tree UI

Дерево является картой темы и навигатором.

Узлы должны показывать состояние знания:

```text
Not started
Learning
Weak
Understood
Strong
```

Не показывать только:

```text
Completed / Not completed
```

---

# 31. Узел должен объяснять контекст

При выборе concept:

```text
Conditioning

Why it matters:
Required to understand CFG and text-to-image conditioning.

Prerequisites:
✓ Diffusion process
✓ Neural networks

Weak prerequisite:
⚠ Representation of conditioning
```

---

# 32. Explore Mode

Пользователь может свободно исследовать graph.

Но:

> **Read ≠ Mastered**

Открытие листа или прочтение текста не должно автоматически повышать mastery так же, как assessment.

---

# 33. Learn Mode

Это основной guided experience.

Показывать:

```text
Current concept
Why it matters
Time estimate
Current progress
Current mastery
Next action
```

Пример:

```text
Reverse Diffusion

Why:
Core mechanism behind generation.

Estimated:
12 min

Progress:
4 / 9 concepts

Next:
Explain reverse process in your own words.
```

---

# 34. Verify Mode

После сессии:

> Can I actually explain this?

Контент скрывается.

Система проверяет пользователя через recall, explanation и application.

---

# 35. AI Tutor

AI Tutor должен быть контекстным, а не просто ChatGPT внутри продукта.

Он должен знать:

```text
Topic
Goal
Target level
Current session
Current concept
Time budget
Current mastery
Previous errors
Misconceptions
Learning history
```

Если пользователь говорит:

> «Я всё равно не понимаю reverse diffusion».

Tutor должен учитывать текущую ошибку и не начинать весь topic с нуля.

---

# 36. Time-aware AI Tutor

Если осталось 5 минут:

не давать 20-минутную лекцию.

Вместо этого:

> Используем оставшиеся 5 минут, чтобы закрепить ключевую идею.

AI Tutor должен уважать time budget.

---

# 37. Learning Journey после первой сессии

После завершения:

```text
Diffusion Models

Current level:
Solid Understanding

Goal:
Understand

Status:
ENOUGH
```

И ниже:

```text
Want to go deeper?

Practical Application
~3–5h

Implementation
~6–10h

Advanced Theory
~8–15h

Research
~20h+
```

Пользователь сам выбирает следующий этап.

---

# 38. Next milestone должен быть объяснён

Не:

> Next lesson: SDE.

А:

> **Next milestone: Advanced Theory**
>
> Ты разберёшься в математической формулировке diffusion models, score-based models и SDE.
>
> Это имеет смысл, если ты хочешь читать research papers или глубже понимать теорию.

Так пользователь понимает:

```text
What
Why
Effort
Outcome
```

---

# 39. Динамическая оценка времени

Не давать ложную точность:

```text
4h 17m
```

Предпочтительно:

```text
~3–5 hours
```

После фактического обучения оценку можно обновлять.

Например:

```text
Initial:
3–5h

After 1h:
You are progressing faster than expected.

Remaining:
~1.5–2.5h
```

---

# 40. Learning ETA

Система может работать как навигатор:

```text
Current:
Solid Understanding

Next:
Practical Application

Estimated:
3–5h
```

После каждой сессии ETA обновляется на основе реального performance.

---

# 41. Не заставлять пользователя продолжать

Если пользователь достиг цели:

```text
You are done for this goal.
```

Не создавать искусственный endless learning loop.

Но можно предложить:

```text
Go deeper
Review later
Explore related topic
Stop
```

---

# 42. Spaced Review

После быстрого освоения можно предложить retention layer:

```text
Tomorrow:
5 min recall

In 3 days:
Quick assessment

In 7 days:
Application
```

Это вторичный слой.

Основной продукт:

> Fast Understanding.

Retention:

> Keep It.

---

# 43. Topic Journey

История пользователя должна выглядеть примерно так:

```text
Diffusion Models

✓ Awareness
✓ Basic Understanding
✓ Solid Understanding
→ Practical Application
○ Implementation
○ Advanced Theory
○ Research
```

При этом разные ветки могут развиваться независимо.

---

# 44. Пользователь должен иметь возможность менять цель

Например:

Первоначально:

```text
Understand Diffusion Models
```

Через неделю:

```text
Implement Diffusion Models
```

Система не должна начинать с нуля.

Она использует существующий Learner Model.

```text
Current mastery:
Solid Understanding

New goal:
Implementation

Missing:
Math
Training pipeline
U-Net details
Sampling implementation
```

И строит новый curriculum только вокруг missing knowledge.

---

# 45. Полный пример

Пользователь:

> Хочу быстро понять Diffusion Models.

Выбирает:

```text
Goal:
Solid Understanding

Time:
2 hours
```

Система:

```text
Diagnostic
↓
Current level: Beginner
↓
Generate graph
↓
Select minimum sufficient curriculum
```

Сессия:

```text
Core idea
10m

Forward diffusion
12m

Reverse diffusion
15m

DDPM
20m

Training objective
15m

Sampling
10m

Conditioning
8m

Synthesis
10m

Assessment
10m
```

После:

```text
Result:
Solid Understanding

Strong:
Core idea
Forward process
Reverse process
DDPM

Developing:
Sampling
Conditioning
```

Система:

```text
For your current goal:
ENOUGH

If you want to continue:

Practical Application
~3–5h

Implementation
~6–10h

Advanced Theory
~8–15h

Research
~20h+
```

Пользователь выбирает:

```text
Practical Application
```

Новая сессия начинается уже с текущего mastery.

---

# 46. Что продукт НЕ должен делать

Не превращать продукт в:

- генератор бесконечного текста;
- обычный chatbot;
- обычную LMS;
- библиотеку курсов;
- passive reading app;
- quiz app;
- красивое дерево без pedagogical logic.

---

# 47. Основное отличие от ChatGPT

Не пытаться быть «умнее ChatGPT».

Разница:

```text
ChatGPT

Question
 ↓
Answer
```

Продукт:

```text
Goal
 ↓
Current knowledge
 ↓
Knowledge graph
 ↓
Minimum sufficient curriculum
 ↓
Time budget
 ↓
Explain
 ↓
Recall
 ↓
Apply
 ↓
Assess
 ↓
Adapt
 ↓
Mastery
 ↓
Next milestone
```

Формула позиционирования:

> **ChatGPT gives you answers. The Learning Engine manages your learning.**

---

# 48. Основное отличие от репетитора

Не утверждать, что AI всегда лучше человека.

Сильный репетитор может превосходить продукт в:

- сложных индивидуальных объяснениях;
- мотивации;
- accountability;
- эмоциональном контакте;
- практическом опыте;
- длительной подготовке.

Продукт должен выигрывать в:

- доступности;
- цене;
- мгновенном старте;
- постоянной доступности;
- структурировании темы;
- диагностике;
- адаптации;
- tracking mastery;
- коротких учебных сессиях.

Позиционирование:

> **Не замена хорошему репетитору, а персональный learning engine, доступный в любой момент.**

---

# 49. Основное отличие от обычных курсов

Обычный курс:

```text
Fixed curriculum
Fixed depth
Fixed order
```

Learning Engine:

```text
Goal
+
Current knowledge
+
Available time
+
Performance
=
Dynamic curriculum
```

---

# 50. Архитектура домена

Рефакторинг желательно строить вокруг следующих сущностей:

```text
Topic
KnowledgeGraph
KnowledgeNode
LearningGoal
MasteryLevel
LearningJourney
LearningMilestone
LearningSession
Curriculum
CurriculumItem
LearnerModel
ConceptMastery
Misconception
Assessment
Question
Attempt
LearningEvent
Review
```

---

# 51. Основные сервисы

Желательная логическая декомпозиция:

```text
KnowledgeGraphEngine
CurriculumEngine
LearningSessionEngine
LearnerModelService
AssessmentEngine
MasteryEngine
AdaptiveLearningEngine
AITutorService
ReviewScheduler
```

Не обязательно создавать физически отдельный микросервис для каждого.

Это domain boundaries, а не требование распределённой архитектуры.

---

# 52. KnowledgeGraphEngine

Отвечает за:

- генерацию graph;
- нормализацию nodes;
- prerequisites;
- relationships;
- importance;
- difficulty;
- estimated learning time;
- deduplication;
- graph validation.

Не должен решать, что пользователь изучает прямо сейчас.

---

# 53. CurriculumEngine

Отвечает за:

```text
Topic
+
Goal
+
Current mastery
+
Time budget
+
Desired depth
```

и выдаёт:

```text
Minimum sufficient curriculum
```

Это один из центральных компонентов продукта.

---

# 54. LearningSessionEngine

Отвечает за:

- progression;
- current item;
- timing;
- state;
- transitions;
- adaptation;
- session completion;
- resume.

Не должен содержать UI-specific logic.

---

# 55. LearnerModelService

Хранит:

```text
Mastery
Confidence
Errors
Misconceptions
History
```

и предоставляет состояние пользователя Curriculum Engine и AI Tutor.

---

# 56. AssessmentEngine

Отвечает за:

- question generation;
- question selection;
- scoring;
- explanation evaluation;
- application evaluation;
- misconception detection.

---

# 57. MasteryEngine

Преобразует evidence в mastery.

Не считать:

```text
Read page = mastery
```

Учитывать:

```text
Recall
Explanation
Application
Transfer
```

Можно использовать probabilistic / heuristic model.

Главное — отделить:

```text
content consumption
```

от:

```text
evidence of learning
```

---

# 58. AdaptiveLearningEngine

При каждом meaningful learning event решает:

```text
Continue
Repeat
Simplify
Add prerequisite
Deepen
Skip
Change order
End session
```

---

# 59. AI Tutor Service

AI Tutor получает структурированный context:

```text
topic
goal
target level
current node
current mastery
misconceptions
session time remaining
recent attempts
```

И возвращает educational response.

Не разрешать UI напрямую собирать произвольный prompt из десятков компонентов.

---

# 60. ReviewScheduler

Вторичный компонент.

Отвечает за:

```text
review due
review interval
review type
```

Не должен определять основной curriculum.

---

# 61. Just-in-time generation

Не генерировать весь подробный контент всего graph заранее.

Генерировать:

```text
Graph first
Curriculum second
Detailed content just-in-time
```

Для текущего concept:

```text
Explanation
Example
Retrieval question
Application
Feedback
```

Это:

- дешевле;
- быстрее;
- адаптивнее;
- уменьшает количество ненужного контента.

---

# 62. AI cost architecture

Не отправлять каждое действие в сильнейшую модель.

Использовать:

```text
Deterministic logic:
- timing
- scheduling
- state
- basic scoring
- persistence

Fast / cheap model:
- formatting
- simple generation
- basic questions

Strong model:
- curriculum reasoning
- misconception analysis
- difficult explanation
- open-ended assessment
```

---

# 63. Quality control

AI-generated graph и curriculum нужно валидировать.

Проверять:

- duplicates;
- missing prerequisites;
- circular dependencies;
- overly broad nodes;
- overly granular nodes;
- irrelevant concepts;
- unrealistic timing;
- broken learning sequence.

---

# 64. Источники и factual reliability

Для тем, где точность критична, предусмотреть sources / citations.

Особенно:

- medicine;
- law;
- finance;
- scientific topics;
- exam preparation.

AI-generated content не должен автоматически считаться достоверным.

---

# 65. UI — главный экран темы

Рекомендуемая структура:

```text
┌──────────────────────────────────────────────────────────┐
│ Diffusion Models                         1h 42m remaining │
├───────────────┬──────────────────────────┬───────────────┤
│ Contents      │                          │ Session        │
│               │      Knowledge Tree      │               │
│ Core idea     │                          │ Current        │
│ Forward       │       ●                 │ Reverse        │
│ Reverse       │      / \                │ Diffusion      │
│ DDPM          │     ●   ●               │               │
│ Sampling      │        /                 │ Why it matters│
│ ...           │       ●                  │               │
│               │                          │ [Continue]    │
└───────────────┴──────────────────────────┴───────────────┘
```

Существующий UI можно сохранить концептуально.

Но состояние узлов и session context должны стать динамическими.

---

# 66. Topic overview screen

Перед обучением:

```text
Diffusion Models

Your goal:
Solid Understanding

Your level:
Beginner

Time:
2 hours

Estimated result:
Solid Understanding

You will learn:
✓ Core mechanism
✓ Forward / reverse process
✓ DDPM
✓ Training
✓ Sampling

We will skip:
SDE details
Recent architectures
Advanced samplers

[Start 2-hour session]
```

---

# 67. Post-session screen

```text
SESSION COMPLETE

Diffusion Models

Goal:
Solid Understanding

Achieved:
Solid Understanding

Strong:
✓ Core idea
✓ Forward diffusion
✓ Reverse diffusion
✓ DDPM

Developing:
⚠ Sampling
⚠ Conditioning

For your current goal:
ENOUGH

Continue deeper?

→ Practical Application      ~3–5h
→ Implementation             ~6–10h
→ Advanced Theory            ~8–15h
→ Research                   ~20h+

[Done]
```

---

# 68. Long-term topic screen

```text
DIFFUSION MODELS

Learning Journey

✓ Awareness
✓ Basic Understanding
✓ Solid Understanding
→ Practical Application
○ Implementation
○ Advanced Theory
○ Research
```

Если пользователь выбирает другой branch:

```text
Practical Application
```

создаётся новая session curriculum.

---

# 69. Micro topics

Для маленькой темы не создавать огромный graph.

Например:

```text
What is dropout?
```

может стать:

```text
5–15 minute micro-session
```

Продукт должен автоматически определять масштаб.

---

# 70. Большие темы

Для:

```text
Artificial Intelligence
```

не пытаться провести пользователя через весь graph.

Система должна уточнить цель:

```text
AI fundamentals
Machine Learning
LLMs
AI Engineering
Generative AI
Research
```

или предложить high-level map для Explore.

---

# 71. Главные продуктовые метрики

Не считать основными:

- количество деревьев;
- количество страниц;
- количество кликов;
- количество AI messages;
- время в приложении.

Основные:

```text
Learning Gain
Time to Target Mastery
Learning Gain / Minute
Immediate Recall
Delayed Recall
Application Accuracy
Transfer Accuracy
Session Completion
Milestone Progression
```

---

# 72. Ключевой эксперимент

Самая важная продуктовая гипотеза:

> **Может ли система дать пользователю больше полезного знания за то же время, чем обычное использование ChatGPT / пассивное чтение?**

Эксперимент:

```text
Group A:
Ordinary ChatGPT

Group B:
Learning Engine
```

Одинаковая:

```text
Topic
Initial knowledge
Time budget
Target
```

Проверка:

```text
Immediately
3 days
7 days
```

Измерить:

```text
Recall
Application
Transfer
Confidence
Time spent
```

Если Learning Engine даёт лучший результат при сопоставимом времени — это фундаментальное доказательство ценности продукта.

---

# 73. MVP

Не реализовывать весь vision сразу.

Минимальный MVP:

```text
1. Topic input
2. Goal selection
3. Time budget
4. Diagnostic
5. Knowledge graph
6. Minimum sufficient curriculum
7. Learning session
8. Explain
9. Recall
10. Apply
11. Feedback
12. Mastery
13. Final assessment
14. Next milestone recommendation
```

Это уже проверяет центральную гипотезу.

---

# 74. Второй этап

После проверки MVP:

```text
Learner Model
Misconceptions
Adaptive curriculum
Dynamic ETA
Topic journey
Multiple learning branches
Review scheduling
Contextual AI Tutor
```

---

# 75. Что пока НЕ является приоритетом

Не тратить значительные ресурсы на:

- social;
- leaderboard;
- badges;
- сложную gamification;
- огромную библиотеку готовых курсов;
- сложный календарь;
- сложную долгосрочную аналитику;
- визуальные эффекты ради визуальных эффектов.

Сначала доказать:

> **Fast learning works.**

---

# 76. Инструкция AI-агенту по рефакторингу

## Перед изменениями

1. Изучить существующую кодовую базу.
2. Определить текущую архитектуру.
3. Найти существующий Knowledge Tree.
4. Найти Book Mode.
5. Найти Test Generation.
6. Найти Learning Plan.
7. Найти user state / progress.
8. Найти LLM integration.
9. Найти persistence.
10. Составить карту существующих компонентов.

## Не делать blind rewrite.

Переиспользовать существующие рабочие части, если они совместимы с новой моделью.

---

# 77. Целевой порядок рефакторинга

```text
Current Product
      ↓
Extract domain models
      ↓
Introduce LearningSession
      ↓
Introduce LearningGoal
      ↓
Introduce Mastery
      ↓
Separate KnowledgeGraph from Curriculum
      ↓
Introduce Time Budget
      ↓
Introduce Assessment evidence
      ↓
Introduce Adaptive Learning
      ↓
Introduce Milestones
      ↓
Connect existing UI
```

---

# 78. Главное архитектурное правило

Не делать:

```text
React component
    ↓
LLM call
    ↓
random state update
```

Предпочтительно:

```text
UI
 ↓
Application / Controller
 ↓
Domain services
 ├── CurriculumEngine
 ├── LearningSessionEngine
 ├── LearnerModel
 ├── AssessmentEngine
 └── MasteryEngine
 ↓
Infrastructure
 ├── LLM
 ├── DB
 └── External services
```

---

# 79. Separation of concerns

UI не должен знать:

- как рассчитывается mastery;
- почему concept выбран;
- как выбирается next milestone;
- как строится curriculum;
- как определяется prerequisite.

UI должен получать:

```text
CurrentSessionState
Curriculum
ConceptState
Mastery
NextMilestones
```

и отображать их.

---

# 80. Acceptance criteria

После рефакторинга пользователь должен иметь возможность:

### Start

- ввести тему;
- выбрать цель;
- выбрать время;
- пройти diagnostic.

### Plan

- увидеть current level;
- увидеть target;
- увидеть estimated duration;
- увидеть curriculum;
- понять, почему эти concepts выбраны.

### Learn

- получать объяснения;
- видеть примеры;
- отвечать на retrieval questions;
- выполнять application tasks;
- получать feedback.

### Adapt

- получить более простое объяснение;
- получить prerequisite;
- пропустить уже известное;
- изменить глубину;
- адаптировать remaining time.

### Verify

- пройти final assessment;
- получить mastery;
- увидеть strong / weak concepts;
- увидеть misconceptions.

### Continue

- понять, достигнута ли цель;
- увидеть следующий milestone;
- увидеть несколько возможных направлений;
- увидеть примерную стоимость по времени;
- начать новую session без потери предыдущего прогресса.

---

# 81. Самый важный UX-принцип

В каждый момент пользователь должен понимать:

```text
Where am I?
Why am I learning this?
How much time will it take?
What will I be able to do afterward?
What should I learn next?
```

Если UI не отвечает на эти вопросы, система превращается в обычный content browser.

---

# 82. Самый важный педагогический принцип

> **Read ≠ Know.**

И:

> **Know ≠ Can Apply.**

Поэтому mastery должна основываться на evidence:

```text
Recall
Explanation
Application
Transfer
```

а не на:

```text
Pages viewed
Nodes opened
Time spent
```

---

# 83. Самый важный алгоритмический принцип

> **Do not maximize content. Maximize learning gain under constraints.**

Ограничения:

```text
Time
Current knowledge
Goal
Cognitive load
Difficulty
```

---

# 84. Самый важный продуктовый принцип

> **User decides how far to go.**

Система предлагает:

```text
Current level
Next meaningful milestone
Estimated effort
Expected capability
Alternative paths
```

Но не заставляет пользователя изучать больше, чем ему нужно.

---

# 85. Финальная модель продукта

```text
                  USER
                    │
             Topic + Goal + Time
                    │
                    ▼
             CURRENT KNOWLEDGE
                    │
                    ▼
             KNOWLEDGE GRAPH
                    │
                    ▼
          MINIMUM SUFFICIENT PATH
                    │
                    ▼
             LEARNING SESSION
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
     Explain     Recall      Apply
        │           │           │
        └───────────┼───────────┘
                    ▼
                 Feedback
                    │
                    ▼
              Update Mastery
                    │
                    ▼
              Final Assessment
                    │
                    ▼
             CURRENT MILESTONE
                    │
              ┌─────┴─────┐
              ▼           ▼
            ENOUGH      CONTINUE
                          │
                          ▼
                   NEXT MILESTONE
                          │
                          ▼
                    NEW SESSION
                          │
                          ▼
                         ...
```

---

# 86. Финальная формулировка

Продукт должен позволять человеку:

> **Быстро понять любую разумно ограниченную тему настолько глубоко, насколько ему необходимо, а затем при желании продолжить углубление по персональному пути, который система строит исходя из его текущих знаний, цели и следующего желаемого результата.**

Ключевая формула:

```text
ANY TOPIC
+
GOAL
+
TIME
+
CURRENT KNOWLEDGE
        ↓
AI LEARNING ENGINE
        ↓
MINIMUM SUFFICIENT CURRICULUM
        ↓
ACTIVE LEARNING
        ↓
MEASURED MASTERY
        ↓
NEXT MILESTONE
        ↓
DEEPER LEARNING WHEN NEEDED
```

Главная идея продукта:

> **Learn as much as you need, as quickly as possible — and go deeper only when you need to.**
