const Map<String, String> levelLabel = {
  'awareness': 'Ознакомление',
  'basic_understanding': 'Базовое понимание',
  'solid_understanding': 'Уверенное понимание',
  'practical_application': 'Практическое применение',
  'advanced': 'Продвинутый',
  'expert': 'Эксперт',
};

const Map<String, String> goalLabel = {
  'overview': 'Обзор',
  'deep': 'Глубокое изучение',
  'exam': 'Подготовка к экзамену',
};

const Map<String, String> typeLabel = {
  'explain': 'Объяснение',
  'example': 'Пример',
  'recall': 'Воспроизведение',
  'apply': 'Применение',
  'assessment': 'Оценка',
  'synthesis': 'Синтез',
};

const Map<String, String> activityTypeLabel = {
  'explain': 'Изучаем понятие',
  'example': 'Разбираем пример',
  'recall': 'Проверяем запоминание',
  'apply': 'Применяем на практике',
};

/// Подпись понятия для UI: label узла из графа, а если его нет — id без
/// scoped-суффикса (`n3_1~e6d461c2` → `n3_1`).
///
/// Внутренние идентификаторы движка пользователю не показываем: в списках
/// «слабые», «повторить», «мисконцепции» нужны понятные названия понятий.
String conceptTitle(String nodeId, String? label) {
  final trimmed = label?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  final sep = nodeId.indexOf('~');
  return sep > 0 ? nodeId.substring(0, sep) : nodeId;
}

