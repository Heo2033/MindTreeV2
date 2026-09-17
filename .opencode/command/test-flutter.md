---
description: Прогнать статический анализ и тесты mindtree_flutter (flutter analyze + flutter test). Можно передать фильтр/файл теста.
agent: testing
---

Запусти статический анализ и тесты Flutter-клиента `mindtree_flutter` и сообщи результат.

Команды (выполняй из `mindtree_flutter/`):
1. `flutter analyze`
2. `flutter test $ARGUMENTS` (если аргументы есть) или `flutter test` (все тесты)

Ожидания:
- Анализ без новых ошибок/предупреждений по изменённым файлам.
- Тесты зелёные: router, scoped_ids, prompts (регрессия `{{TOKEN}}`), graph layout/canvas.

Если тесты падают — сообщи причину и предложи fix (не редактируя продакшен-код напрямую,
если работаешь как testing-агент с edit: deny; при правках согласуй с основным агентом).