# План: Режим подготовки к ЕГЭ / ОГЭ в MindTreeV2

## Контекст

MindTreeV2 — универсальный AI-движок адаптивного обучения. Текущий фокус — обучение и понимание темы через генерацию графов знаний, адаптивные сессии и оценку освоения.

**Цель:** добавить режим подготовки к ЕГЭ/ОГЭ по всем предметам, с предгенерированными деревьями знаний, дашбордом прогресса и симуляцией экзамена.

**Ключевой инсайт:** если пользователь пройдёт все темы предмета и поймёт материал — он сдаст ЕГЭ. Для максимума баллов нужны дополнительные тренировки с форматом экзамена (таймер, типы заданий, подсчёт баллов).

---

## Архитектурное решение: ExamPack

Новый доменный объект `ExamPack` — упакованный набор предгенерированных графов знаний по предмету, связанный со структурой экзамена.

```
ExamPack
├── id, name, subject, exam_type ("ЕГЭ"/"ОГЭ"/...)
├── description, icon, difficulty
├── exam_structure (JSON: части, номера, баллы, веса)
└── trees[]
    ├── tree_id, name, topic_id (привязка к сгенерированному графу)
    ├── exam_tasks[] (номера заданий ЕГЭ, покрытых этой темой)
    └── order (порядок изучения)
```

---

## Фаза 1: Инфраструктура (Импорт/Экспорт графов)

**Цель:** уметь сохранять и загружать предгенерированные графы знаний.

### 1.1 Серверная часть

**Новая таблица `exam_packs`:**

| Колонка | Тип | Описание |
|---|---|---|
| `id` | TEXT PK | `ep_<uuid>` |
| `name` | TEXT | Название пакета |
| `subject` | TEXT | Предмет (history, society, math, ...) |
| `exam_type` | TEXT | ЕГЭ / ОГЭ / ДРУГОЕ |
| `description` | TEXT | Описание |
| `icon` | TEXT | Иконка/эмодзи |
| `exam_structure_json` | TEXT | JSON со структурой экзамена |
| `created_at` | TEXT | datetime |

**Новая таблица `exam_pack_trees`:**

| Колонка | Тип | Описание |
|---|---|---|
| `id` | TEXT PK | `ept_<uuid>` |
| `pack_id` | TEXT FK | → exam_packs.id |
| `tree_name` | TEXT | Название дерева (темы) |
| `topic_id` | TEXT FK | → topics.id (шаблонный topic) |
| `exam_tasks_json` | TEXT | JSON массив номеров заданий ЕГЭ |
| `sort_order` | INTEGER | Порядок изучения |

**Новые маршруты API (`server/src/routes/exam-packs.ts`):**

- `GET /api/exam-packs` — список доступных пакетов
- `GET /api/exam-packs/:id` — пакет с деревьями
- `POST /api/exam-packs/:id/start` — создаёт topics для пользователя и копирует графы
- `POST /api/exam-packs/import` — импорт пакета из JSON (admin)
- `GET /api/exam-packs/:id/export` — экспорт пакета как JSON (admin)

**Новый движок (`server/src/domain/ExamPackEngine.ts`):**

- `importPack(json)` — валидирует и создаёт пакет + все деревья в БД
- `exportPack(packId)` — сериализует пакет со всеми нодами в JSON
- `startPackForUser(packId)` — для каждого дерева создаёт topic, копирует структуру графа, привязывает к learner model
- `progress(packId, userId)` — считает % завершённых topics, средний mastery

### 1.2 Формат импорта JSON

```json
{
  "name": "ЕГЭ по истории — Профиль",
  "subject": "history",
  "exam_type": "ЕГЭ",
  "description": "Полная программа подготовки к ЕГЭ по истории (профильный уровень)",
  "exam_structure": {
    "parts": [
      { "name": "Часть 1", "tasks": [1,2,3,4,5,6,7,8], "max_score": 8 },
      { "name": "Часть 2", "tasks": [9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25], "max_score": 38 }
    ]
  },
  "trees": [
    {
      "name": "Древняя Русь (IX–XII вв.)",
      "exam_tasks": [1, 2, 3],
      "graph": {
        "nodes": [
          {
            "id": "n1_root",
            "label": "Древняя Русь",
            "one_liner": "...",
            "concept_type": "topic",
            "importance": 1.0,
            "difficulty": 0.3,
            "children": [...]
          }
        ]
      }
    }
  ]
}
```

### 1.3 Фронтенд

- Новая секция на Home-экране: «Подготовка к экзаменам» с карточками пакетов
- Карточки: иконка предмета, название, описание, прогресс, кнопка «Начать»

### 1.4 Файлы для создания/изменения

| Компонент | Файл | Действие |
|---|---|---|
| Типы | `packages/types/src/exam-pack.ts` | Создать |
| Типы (index) | `packages/types/src/index.ts` | Добавить экспорт |
| Таблицы БД | `server/src/db/connection.ts` | Добавить в `migrate()` |
| Движок | `server/src/domain/ExamPackEngine.ts` | Создать |
| Маршруты | `server/src/routes/exam-packs.ts` | Создать |
| Сервер index | `server/src/index.ts` | Зарегистрировать маршруты |
| API клиент | `apps/web/src/api/endpoints.ts` | Добавить endpoints |
| API клиент | `apps/web/src/api/client.ts` | Добавить функции |
| Stores | `apps/web/src/stores/examPackStore.ts` | Создать |
| UI | `apps/web/src/screens/ExamPacks.tsx` | Создать |
| UI | `apps/web/src/screens/ExamPackDetail.tsx` | Создать |
| Роутинг | `apps/web/src/App.tsx` | Добавить маршруты |
| Home | `apps/web/src/screens/Home.tsx` | Добавить секцию |
| Скрипт | `scripts/generate-exam-pack.ts` | Создать |

---

## Фаза 2: ExamPack Dashboard (Управление прогрессом)

**Цель:** видеть общий прогресс по всем деревьям пакета.

### 2.1 Сервер

**`ExamPackEngine.progress(packId, userId)`:**
- Количество завершённых topics / всего
- Средний mastery по деревьям
- Статус каждого дерева: `locked` / `available` / `in_progress` / `completed`
- Привязка к `learner_models` — кросс-тематический прогресс

### 2.2 Фронтенд — Экран `ExamPackDashboard`

**Маршрут:** `/exam-pack/:packId`

- Прогресс-бар по всему пакету (X из Y тем завершено)
- Сетка деревьев с карточками:
  - Название темы
  - % освоения (mastery)
  - Статус (locked/available/in_progress/completed)
  - Номера заданий ЕГЭ, которые покрывает тема
  - Кнопка «Продолжить» / «Начать»
- Фильтры: все / незавершённые / по номерам ЕГЭ
- При клике на дерево → переход в TopicShell (обычный flow: сессия, квиз, тьютор)

### 2.3 Файлы

| Компонент | Файл | Действие |
|---|---|---|
| UI | `apps/web/src/screens/ExamPackDashboard.tsx` | Создать |
| Stores | `apps/web/src/stores/examPackStore.ts` | Добавить progress |
| Роутинг | `apps/web/src/App.tsx` | Добавить маршрут dashboard |

---

## Фаза 3: Exam Simulation (Тренировка в формате экзамена)

**Цель:** симуляция полного экзамена с таймером и подсчётом баллов.

### 3.1 Новый движок `ExamSimulationEngine`

**Сервер (`server/src/domain/ExamSimulationEngine.ts`):**

- Загружает `exam_structure` из ExamPack
- Генерирует задания по номерам через LLM (или берёт из предгенерированного банка)
- Управляет состоянием: `in_progress` / `completed` / `timeout`
- Подсчитывает processинговые баллы по official шкале
- Записывает попытки в `assessment_attempts`

**Новая таблица `exam_simulations`:**

| Колонка | Тип | Описание |
|---|---|---|
| `id` | TEXT PK | `esim_<uuid>` |
| `pack_id` | TEXT FK | → exam_packs.id |
| `user_model_id` | TEXT FK | → learner_models.id |
| `status` | TEXT | active / completed / timeout |
| `started_at` | TEXT | Время начала |
| `finished_at` | TEXT | Время окончания |
| `time_limit_minutes` | INTEGER | Лимит (355 для ЕГЭ) |
| `tasks_json` | TEXT | JSON с заданиями и ответами |
| `total_score` | INTEGER | Итоговый балл |
| `max_score` | INTEGER | Максимальный балл |

### 3.2 API маршруты (`server/src/routes/exam-simulations.ts`)

- `POST /api/exam-simulations` — создать симуляцию (выбор: все задания / часть / слабые места)
- `GET /api/exam-simulations/:id` — текущее состояние + оставшееся время
- `POST /api/exam-simulations/:id/answer` — ответить на задание (номер, ответ)
- `POST /api/exam-simulations/:id/finish` — завершить, получить баллы + разбор
- `GET /api/exam-simulations/:id/review` — разбор ответов с правильными

### 3.3 Типы заданий ЕГЭ

Расширить `AssessmentQuestion` или создать отдельную модель `ExamTask`:

| Тип | Описание | Реализация |
|---|---|---|
| `multiple_choice` | MCQ (A/B/C/D) | MCQ UI (уже есть в Quiz) |
| `short_answer` | Краткий ответ (слово/число/дата) | Text input + валидация |
| `matching` | Соответствие (пары) | Drag-and-drop / select |
| `sequence` | Хронологическая последовательность | Drag-and-drop排序 |
| `document_analysis` | Работа с документом | Текст + MCQ/текст |
| `essay` | Сочинение/рассуждение | Textarea + LLM-оценка |
| `map_task` | Работа с картой | MCQ с привязкой к карте |

### 3.4 Фронтенд — Экран `ExamSimulation`

**Маршрут:** `/exam-simulation/:id`

- **Таймер** обратного отсчёта (顶部)
- **Навигация** по номерам заданий (侧边栏 с превью: отвечено/не отвечено/ flagged)
- **Область задания:** типо-специфичный рендеринг
  - MCQ → кнопки A/B/C/D (как в Quiz)
  - Текстовый ответ → input/textarea
  - Документ → раздельная панель (документ слева, вопрос справа)
  - Сочинение → textarea с подсказкой по объёму
- **Кнопка «Завершить»** с подтверждением
- **Экран результатов:**
  - Общий балл / максимум
  - Разбор по заданиям: правильный ответ, ваш ответ, пояснение
  - Рекомендации: какие темы подтянуть
  - График баллов (если есть предыдущие попытки)

### 3.5 Файлы

| Компонент | Файл | Действие |
|---|---|---|
| Типы | `packages/types/src/exam-simulation.ts` | Создать |
| Движок | `server/src/domain/ExamSimulationEngine.ts` | Создать |
| Маршруты | `server/src/routes/exam-simulations.ts` | Создать |
| Сервер index | `server/src/index.ts` | Зарегистрировать |
| API клиент | `apps/web/src/api/endpoints.ts` | Добавить |
| Stores | `apps/web/src/stores/examSimulationStore.ts` | Создать |
| UI | `apps/web/src/screens/ExamSimulation.tsx` | Создать |
| UI | `apps/web/src/screens/ExamResults.tsx` | Создать |
| UI components | `apps/web/src/components/ExamTask*.tsx` | Создать (по типам заданий) |
| Роутинг | `apps/web/src/App.tsx` | Добавить маршруты |

---

## Фаза 4: Предгенерация контента

### 4.1 Скрипт генерации (`scripts/generate-exam-pack.ts`)

- Принимает JSON-конфиг пакета (название, темы, структура экзамена)
- Для каждой темы запускает `KnowledgeGraphEngine.generate()` через прямой вызов (без HTTP)
- Сохраняет результат в БД как шаблонный topic + knowledge_nodes
- Запуск: `npx tsx scripts/generate-exam-pack.ts --config history-ege.json`

### 4.2 Копирование графов при старте для пользователя

При `startPackForUser()`:
1. Создаётся новый `topic` для пользователя
2. Все `knowledge_nodes` из шаблонного topic копируются с новым `topic_id` и пересчитанными scoped IDs
3. `content_loaded = 0` — контент генерируется lazy (как сейчас)
4. Структура графа (дерево) сохраняется, LLM генерирует только текст

Это экономит LLM-вызовы (структура уже готова) и даёт пользователям персонализированный контент.

### 4.3 Файлы

| Компонент | Файл | Действие |
|---|---|---|
| Скрипт | `scripts/generate-exam-pack.ts` | Создать |
| Конфиги | `scripts/packs/history-ege.json` | Создать (первый пилот) |
| Конфиги | `scripts/packs/society-ege.json` | Создать |
| Движок | `server/src/domain/ExamPackEngine.ts` | Добавить `copyGraphForUser()` |

---

## Фаза 5: Масштабирование на все предметы

### Приоритетные предметы

| # | Предмет | Сложность | Особенности |
|---|---|---|---|
| 1 | **Обществознание** | Низкая | Преимущественно MCQ + краткий ответ |
| 2 | **Математика (база)** | Низкая | MCQ + развёрнутый ответ |
| 3 | **Биология** | Низкая | MCQ + текстовые ответы |
| 4 | **История** | Средняя | Хронология, документы, карты, сочинение |
| 5 | **Русский язык** | Средняя | Правила, тексты, изложение, сочинение |
| 6 | **Литература** | Средняя | Анализ текста, сочинение |
| 7 | **Химия** | Средняя | Формулы (KaTeX), расчёты |
| 8 | **Физика** | Средняя | Формулы, расчёты, задачи |
| 9 | **Информатика** | Средняя | Код, алгоритмы, таблицы |
| 10 | **География** | Низкая | MCQ + работа с картами |
| 11 | **Математика (профиль)** | Высокая | Развёрнутые решения, KaTeX (уже есть!) |
| 12 | **Английский** | Высокая | Аудирование, письмо, устная часть |

### Универсальный ExamPackCreator (UI)

Отдельный экран для создания пакетов (admin):
1. Выбор предмета → показ шаблона структуры экзамена
2. Ввод тем (или загрузка CSV/JSON)
3. LLM генерирует деревья автоматически
4. Превью + редактирование + экспорт

### Файлы

| Компонент | Файл | Действие |
|---|---|---|
| Конфиги | `scripts/packs/*.json` | Создать по одному на предмет |
| UI | `apps/web/src/screens/ExamPackCreator.tsx` | Создать (admin) |

---

## Фаза 6: Аналитика и рекомендации

### Exam Readiness Score

- Расчёт вероятности сдачи на проходный / минимальный / максимальный балл
- На основе текущего mastery + результатов симуляций
- Формула: weighted average по деревьям с весами по количеству заданий ЕГЭ

### Weak Areas Dashboard

- Какие темы/номера заданий требуют доработки
- Группировка: по темам / по типам заданий / по сложности
- Рекомендации: «Повторите тему X, решите N заданий типа Y»

### Study Plan Generator

- Ввод: дата экзамена, текущий прогресс
- Вывод: персональный план «изучить N тем, решить M заданий, провести K симуляций»
- Ежедневные задачи с учётом SRS

### Progress Tracking

- Сравнение с предыдущими попытками
- График баллов по симуляциям
- Heatmap освоения тем

### Файлы

| Компонент | Файл | Действие |
|---|---|---|
| Движок | `server/src/domain/ExamAnalyticsEngine.ts` | Создать |
| Маршруты | `server/src/routes/exam-analytics.ts` | Создать |
| UI | `apps/web/src/screens/ExamAnalytics.tsx` | Создать |
| UI | `apps/web/src/components/ReadinessScore.tsx` | Создать |
| UI | `apps/web/src/components/WeakAreas.tsx` | Создать |

---

## Порядок реализации

| # | Фаза | Зависимости | Ожидаемый результат |
|---|---|---|---|
| 1 | Импорт/экспорт JSON | — | Можно создавать и загружать пакеты через API |
| 2 | ExamPack Dashboard | Фаза 1 | Пользователь видит пакеты и свой прогресс |
| 3 | Exam Simulation | Фаза 1 | Можно тренироваться в формате экзамена |
| 4 | Предгенерация + 1 предмет | Фаза 1-2 | Есть рабочий пакет для конкретного предмета |
| 5 | Остальные предметы | Фаза 4 | Масштабирование на все предметы |
| 6 | Аналитика | Фаза 2-3 | Умные рекомендации и readiness score |

---

## Текущий статус

- [ ] Фаза 1: Инфраструктура
- [ ] Фаза 2: Dashboard
- [ ] Фаза 3: Simulation
- [ ] Фаза 4: Предгенерация контента
- [ ] Фаза 5: Все предметы
- [ ] Фаза 6: Аналитика
