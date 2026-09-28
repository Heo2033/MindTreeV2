# MindTree probe

Headless-прогон доменного ядра MindTree: тот же набор движков, что и в
приложении, но без Flutter и Riverpod. Нужен, чтобы проверить движки и
промпты в CI или локально, не открывая приложение.

## Что проверяет

Полный цикл обучения одним прогоном:

```
createTopic → graph.generate → scopeNodeIds → сохранение узлов → content
→ curriculum → diagnostic → session/activity → assessment → mastery → milestones
```

Поверх результата считаются чистые quality-checks (см. `quality_checks.dart`):
`single_root`, `parent_exists`, `no_cycles`, `level_consistent`,
`one_liner_max_len`, `no_empty_content`, `no_duplicate_labels`, `jargon_free`,
`question_wellformed`, `question_node_known`, `recall_wellformed`,
`apply_wellformed`, `no_duplicate_activity`, `goal_coverage`,
`content_coverage`.

## Запуск

Детерминированный прогон без сети и без ключа:

```powershell
& C:\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\probe\bin\mindtree_probe.dart --mock --out build\probe
```

Живой прогон через реальный провайдер (нужен `provider-config.json`):

```powershell
& tool\gen_config.ps1   # создаёт provider-config.json из server/.env
& C:\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\probe\bin\mindtree_probe.dart `
    --query "теорема остановки" --level 2 --out build\probe-live
```

## Опции

| Флаг | Значение |
| --- | --- |
| `--query <текст>` | Тема прогона. Можно указать несколько раз — каждый запрос станет отдельной темой. По умолчанию один демо-запрос. |
| `--goal <цель>` | Цель обучения. По умолчанию `overview`. |
| `--level <1..5>` | Целевой уровень. По умолчанию `1`. |
| `--minutes <N>` | Бюджет времени. По умолчанию `30`. |
| `--out <каталог>` | Куда положить отчёты. По умолчанию `build/probe`. |
| `--mock` | Детерминированный прогон: fake LLM, без сети. |
| `--max-nodes <N>` | Ограничить дерево. `0` — без лимита. |
| `--skip-content` | Не генерировать контент узлов. |
| `--skip-session` | Не проходить сессию и всё, что после неё. |
| `--keep-db` | Сохранить Drift-БД в `<out>/probe.db` вместо in-memory. |
| `--verbose` | Печатать прогресс по шагам. |

Код возврата: `0` — всё прошло, `1` — есть quality-нарушения уровня `fail`,
`64` — ошибка аргументов, `78` — нет конфига для живого прогона.

## Выходные файлы

| Файл | Детерминированный | Содержит |
| --- | --- | --- |
| `report.json` | да | Полный отчёт: params, запросы, дерево, контент, curriculum, diagnostic, session, ответы, assessment, mastery до/после, milestones, checks, LLM-статистика. |
| `report.md` | да | То же для чтения человеком. |
| `run-stats.json` | **нет** | Wall-clock, число вызовов, ошибки/ретраи. |

`report.json` и `report.md` побайтово совпадают между двумя одинаковыми
`--mock`-прогонами — это проверяется тестом
`test/domain/probe_report_test.dart`.

Чтобы отчёт оставался детерминированным, в него **не** попадают
недетерминированные значения: случайные продакшн-id (`session_*`, `asmt_*`,
`ms_*` — вместо них стабильные алиасы `a0`, `a1`, …) и wall-clock таймстемпы.
Сырые значения остаются в `run-stats.json`.

## Секреты

Probe никогда не печатает и не пишет в отчёт `apiKey` и `baseUrl`.
`provider-config.json` читается только в режиме без `--mock`.

## Проверка детерминизма

```powershell
& C:\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\probe\bin\mindtree_probe.dart --mock --out build\p1
& C:\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\probe\bin\mindtree_probe.dart --mock --out build\p2
(Get-FileHash build\p1\report.json).Hash -eq (Get-FileHash build\p2\report.json).Hash
```

Ожидается `True`. То же проверяет `flutter test test\domain\probe_report_test.dart`.

## Устройство

| Файл | Роль |
| --- | --- |
| `bin/mindtree_probe.dart` | CLI: разбор аргументов, in-memory/file Drift DB, выбор mock или live LLM, запись отчётов. |
| `pipeline.dart` | Сам прогон домена; собирает `ProbeResult` и quality-checks. |
| `probe_result.dart` | DTO результата (`ProbeResult`, `QueryOutcome`, `ProbeParams`, `RunStats`). |
| `report.dart` | Рендер JSON / Markdown / run-stats. Здесь же санитизация недетерминированных id. |
| `fake_llm.dart` | Детерминированный fake LLM: роутинг по видам промптов, готовые ответы, фиксированный usage. |
| `quality_checks.dart` | Чистые проверки дерева/контента/вопросов. |
| `jargon.dart` | Детектор терминов без пояснения. |
| `tree_mapper.dart` | `NodeDraft` → `KnowledgeNode` (повторяет логику приложения). |
