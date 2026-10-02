# tool/review — ревью артефактов MindTree

Headless-оценка того, что система реально выдала пользователю: экспортированного
дерева темы и созданных учебных сессий. Без UI и без Riverpod — как `tool/probe`,
но по уже готовому артефакту, а не по свежей генерации.

Зачем два слоя:

- **детерминированные проверки** (`tree_checks.dart`, `session_checks.dart`) — форма:
  висящие id, длина `one_liner`/`details`, циклы, дубли, бюджет времени,
  контракты вопросов. Работают без сети, ключа и модели;
- **LLM-судья** (`judge.dart`, только с `--judge`) — смысл: неверная формула,
  подмена понятия, выдуманная атрибуция, сложность не по уровню аудитории.

## Запуск

```powershell
# дерево темы (детерминированно, без сети)
& C:\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\review\bin\mindtree_review.dart `
  --tree "$env:USERPROFILE\Downloads\mindtree-диффузионные-модели.json" `
  --out build\review

# сессия из базы приложения (только чтение, БД копируется во временный каталог)
& C:\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\review\bin\mindtree_review.dart `
  --db "$env:LOCALAPPDATA\com.mindtree\app\mindtree.db" --limit 5 --out build\review

# с LLM-судьёй (нужен provider-config.json; ключи в отчёт не попадают)
& C:\flutter\bin\cache\dart-sdk\bin\dart.exe run tool\review\bin\mindtree_review.dart `
  --tree "$env:USERPROFILE\Downloads\mindtree-диффузионные-модели.json" `
  --judge --judge-batches 8 --out build\review
```

### Флаги

| Флаг | Смысл |
| --- | --- |
| `--tree <путь>` | файл экспорта темы; можно указать несколько раз |
| `--db <путь>` | `mindtree.db` приложения, только чтение |
| `--session <id>` | конкретная сессия; без флага — последние `--limit` |
| `--limit <N>` | сколько последних сессий разбирать (20) |
| `--judge` | прогнать LLM-судью (тир `strong`, операция `judge`) |
| `--judge-batches <N>` | максимум пачек узлов судьи (20) |
| `--config <путь>` | провайдерский конфиг (`provider-config.json`) |
| `--out <каталог>` | куда положить отчёты (`build/review`) |
| `--fail-on <fail\|warn>` | порог ненулевого кода возврата (`fail`) |

Коды возврата: `0` — ок, `1` — есть находки, `64` — ошибка аргументов,
`78` — нет файла/конфига.

## Выход

- `review-<kind>-<N>.md` — для чтения: шапка с метриками, итог fail/warn/info,
  находки по кодам, находки судьи, предупреждения инструмента;
- `review-<kind>-<N>.json` — то же машино. Детерминирован: таймстемпов и id
  провайдера в нём нет, поэтому два прогона одного файла совпадают побайтово.

## Имена файлов БД

Drift создаёт `mindtree.db`, `mindtree.db-wal`, `mindtree.db-shm`. `session_loader`
копирует все три во временный каталог и открывает копию: оригинал не
блокируется и не изменяется, незакоммиченные данные из WAL не теряются.

## Коды находок

Коды живут в `TreeCheckCode` / `SessionCheckCode` — строковые константы, они же
попадают в JSON. Уровни: `fail` (блокирует), `warn` (стоит чинить), `info`
(для контекста). Новые проверки добавляются функцией `check*` и одной строкой
в `runTreeChecks` / `runSessionChecks`.
