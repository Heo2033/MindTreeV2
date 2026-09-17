---
description: Запустить кодогенерацию mindtree_flutter (build_runner) с удалением конфликтующих выводов. Сгенерированные *.g.dart файлы коммитятся.
agent: flutter-data
---

Запусти кодогенерацию для Flutter-клиента `mindtree_flutter` и проверь результат.

Команда (из `mindtree_flutter/`):
```
dart run build_runner build --delete-conflicting-outputs $ARGUMENTS
```

Ожидания:
- Сгенерированы/обновлены `*.g.dart` (drift, freezed, riverpod, json_serializable).
- Анализ чистый: после генерации прогнать `flutter analyze`.

Примечание: сгенерированные файлы коммитятся в репозиторий (см. AGENTS.md).