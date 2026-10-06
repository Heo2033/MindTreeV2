import 'dart:convert';

import '../models/activity.dart';

/// Разбор blob активности (`session.activity_json`) в itemId + шаги.
///
/// Blob пишет `LearningActivityService._persistSteps`:
/// `{'itemId': ..., 'steps': [...]}`; исторически встречается и голый список
/// шагов. Любой мусор (невалидный JSON, чужая схема) НЕ бросает исключение —
/// отдаёт пустые шаги: метод зовут из UI-кнопки.
({String? itemId, List<ActivityStep> steps}) parseActivityBlob(String raw) {
  try {
    final parsed = jsonDecode(raw.isEmpty ? '{}' : raw);
    if (parsed is List) {
      return (
        itemId: null,
        steps: parsed
            .whereType<Map<String, dynamic>>()
            .map(ActivityStep.fromJson)
            .toList(),
      );
    }
    if (parsed is Map<String, dynamic>) {
      final stepsRaw = parsed['steps'];
      if (stepsRaw is List) {
        return (
          itemId: parsed['itemId'] as String?,
          steps: stepsRaw
              .whereType<Map<String, dynamic>>()
              .map(ActivityStep.fromJson)
              .toList(),
        );
      }
    }
    return (itemId: null, steps: <ActivityStep>[]);
  } catch (_) {
    return (itemId: null, steps: <ActivityStep>[]);
  }
}

/// Качество завершения концепта по шагам активности.
///
/// Свидетельство результата — только шаг с непустым `correct` (recall/apply с
/// реальной оценкой). У read/explain-шагов `correct == null`: «не отвечал» — не
/// то же самое, что «ответил неверно», поэтому в свидетельство они не идут.
/// Есть хоть один `correct == false` → 'again' (интервал SRS сбрасывается,
/// повтор скоро; ложная мисконцепция `careless` не пишется). Иначе 'correct':
/// все верные либо свидетельств нет вовсе — отсутствие данных не ошибка.
String qualityFromSteps(List<ActivityStep> steps) {
  for (final s in steps) {
    if (s.correct == false) return 'again';
  }
  return 'correct';
}

/// Качество завершения концепта по сырому blob сессии.
///
/// `null`, пустая строка, невалидный JSON и blob ЧУЖОГО itemId → мягкая
/// деградация к 'correct' (прежнее поведение): исключение бросать нельзя, метод
/// зовётся из UI-кнопки «Завершить концепт».
String deriveCompletionQuality(String? activityJson, String itemId) {
  if (activityJson == null || activityJson.isEmpty) return 'correct';
  final parsed = parseActivityBlob(activityJson);
  if (parsed.itemId != null && parsed.itemId != itemId) return 'correct';
  return qualityFromSteps(parsed.steps);
}
