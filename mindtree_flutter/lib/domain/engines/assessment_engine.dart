import 'dart:convert';
import 'dart:math';

import '../../data/database/mindtree_repository.dart';
import '../../data/llm/client.dart';
import '../../data/llm/scheduler.dart';
import '../models/models.dart';

/// A single studied concept used as input for assessment generation.
class AssessmentItem {
  final String nodeId;
  final String label;
  final String oneLiner;
  final String details;

  const AssessmentItem({
    required this.nodeId,
    required this.label,
    required this.oneLiner,
    this.details = '',
  });

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'label': label,
        'oneLiner': oneLiner,
        'details': details,
      };
}

const String _noMetaRule = '- В значениях полей пиши только готовый контент по теме. Запрещены служебные фразы о своих действиях и решениях («Узел помечен как…», «Переименовал узел…», «Этот узел не требует дочерних…», «Исправлено…»).';

const String _alphabetRule = '- Используй только кириллицу, латиницу, цифры и обычную пунктуацию. Запрещены иероглифы и знаки других письменностей (китайские, японские, корейские).\n- Все label, title, one_liner, details — только на русском языке.';

const String _promptAssessment = '''# Роль
Ты — экзаменатор. Проверь, действительно ли пользователь достиг заявленного уровня понимания темы.

# Контекст
Тема: "{{topic}}"
Цель пользователя: {{goal}}
Изученные понятия (в рамках сессии):
{{session_items}}

# Типы вопросов (всего их 6)
Сгенерируй финальную проверку, используя следующие типы:
- **recognition** — узнавание: выбери корректный вариант из четырёх (формулировка, а не заучивание)
- **recall** — припоминание: воспроизведи определение или ключевой факт (multiple choice)
- **explanation** — объясни механизм своими словами (structure matters; rubric обязателен)
- **diagnosis** — найди и объясни ошибку/несоответствие в приведённом утверждении (rubric обязателен)
- **application** — примени знание к новой конкретной ситуации (rubric обязателен)
- **transfer** — перенеси знание на смежную/нестандартную ситуацию (rubric обязателен)

Всего {{question_count}} вопросов. Обеспечь разнообразие типов: это должен быть честный замер, а не только фактология.
Для recognition/recall укажи options и correctAnswer (индекс корректного варианта, начиная с 0).
Для explanation/diagnosis/application/transfer — options=[] и correctAnswer=""; explanation (рубрика) содержит конкретные критерии оценивания: какие элементы должны присутствовать в свободном ответе.

# Формат ответа
Строгий JSON-объект:
{"questions":[{"id":"a1","type":"recall","nodeId":"n2_a","question":"...","options":["A","B","C","D"],"correctAnswer":"0","explanation":"..."},{"id":"a2","type":"explanation","nodeId":"n2_b","question":"Объясните своими словами, как работает X (порядок шагов, причинно-следственные связи).","options":[],"correctAnswer":"","explanation":"Ключевые элементы ответа: 1) ..., 2) ..."}]}

# Примечания
- correctAnswer для recognition/recall — ИНДЕКС правильного варианта (строка "0","1","2","3").
- Вопросы проверяют глубокое понимание, не поверхностную фактологию.

$_noMetaRule
$_alphabetRule

# Язык
Отвечай СТРОГО на русском языке. Вопросы, варианты, рубрики — на русском.

Никакого текста вне JSON. Без ```json и без пояснений.

# Проверь перед ответом
- [ ] Ровно {{question_count}} вопросов
- [ ] Есть вопросы с options (recognition/recall) и открытые вопросы (explanation/diagnosis/application/transfer)
- [ ] У всех открытых вопросов rubric (explanation) содержит конкретные критерии
- [ ] Вопросы проверяют глубокое понимание, не поверхностную фактологию
- [ ] Формат — строго JSON с ключом "questions"''';

String _buildAssessmentPrompt({
  required String topic,
  required String goal,
  required List<AssessmentItem> sessionItems,
  required bool includeApplication,
  required int questionCount,
}) {
  final itemsJson = jsonEncode(sessionItems
      .map((s) => {
            'nodeId': s.nodeId,
            'label': s.label,
            'oneLiner': s.oneLiner,
            'details': s.details.length > 400 ? s.details.substring(0, 400) : s.details,
          })
      .toList());

  return _promptAssessment
      .replaceAll('{{topic}}', topic)
      .replaceAll('{{goal}}', goal)
      .replaceAll('{{session_items}}', itemsJson)
      .replaceAll(RegExp(r'\{\{question_count\}\}'), questionCount.toString())
      .replaceAll('{{include_application}}', includeApplication ? 'true' : 'false');
}

List<AssessmentQuestion> _parseAssessmentResult(String raw) {
  final data = parseLLMJson<dynamic>(raw);
  if (data is! Map<String, dynamic>) return [];
  final questions = data['questions'];
  if (questions is! List) return [];
  final rng = Random();
  return questions.whereType<Map<String, dynamic>>().map((q) {
    final options = q['options'];
    return AssessmentQuestion(
      id: q['id'] is String
          ? q['id'] as String
          : 'a_${rng.nextInt(0xffffff).toRadixString(36)}',
      type: QuestionType.fromString(q['type'] as String? ?? 'recall'),
      nodeId: q['nodeId'] is String ? q['nodeId'] as String : '',
      question: q['question'] is String ? q['question'] as String : '',
      options: options is List ? options.whereType<String>().toList() : null,
      correctAnswer: q['correctAnswer'] is String ? q['correctAnswer'] as String : '',
      explanation: q['explanation'] is String ? q['explanation'] as String : '',
    );
  }).toList();
}

/// Generates and grades diagnostic/quiz/final/mastery assessments.
class AssessmentEngine {
  final MindtreeRepository repo;
  final TreeScheduler scheduler;

  const AssessmentEngine({required this.repo, required this.scheduler});

  Future<Assessment> generate(
    String sessionId,
    String topicId,
    List<AssessmentItem> items, {
    AssessmentType type = AssessmentType.final_,
    int questionCount = 6,
    bool includeApplication = true,
  }) async {
    final topic = await repo.getTopic(topicId);

    final prompt = _buildAssessmentPrompt(
      topic: topic?.name ?? '',
      goal: topic?.goal.name ?? '',
      sessionItems: items,
      includeApplication: includeApplication,
      questionCount: questionCount,
    );

    List<AssessmentQuestion> questions;
    try {
      final res = await scheduler.execute<List<AssessmentQuestion>>(
        'assessment',
        () => prompt,
        _parseAssessmentResult,
      );
      questions = res.result.take(questionCount).toList();
    } catch (_) {
      questions = items.take(questionCount).toList().asMap().entries.map((e) {
        final i = e.key;
        final item = e.value;
        return AssessmentQuestion(
          id: 'fa_$i',
          type: QuestionType.recall,
          nodeId: item.nodeId,
          question: 'Что такое "${item.label}"?',
          options: const [],
          correctAnswer: '',
          explanation: item.oneLiner,
        );
      }).toList();
    }

    final id = 'asmt_${_randomSuffix()}';
    final assessment = Assessment(
      id: id,
      sessionId: sessionId,
      type: type,
      questions: questions,
      startedAt: DateTime.now().toIso8601String(),
    );
    await repo.createAssessment(assessment);

    return assessment;
  }

  Future<void> recordAttempt(
    String assessmentId,
    String questionId,
    String answer,
    bool correct,
    int timeMs, {
    String? feedback,
  }) async {
    final attempt = Attempt(
      id: 'att_${_randomSuffix()}',
      assessmentId: assessmentId,
      questionId: questionId,
      answer: answer,
      correct: correct,
      timeSpentMs: timeMs,
      feedback: feedback,
    );
    await repo.addAttempt(attempt);
  }

  Future<void> finalize(String assessmentId, double score) async {
    final existing = await repo.getAssessment(assessmentId);
    if (existing == null) return;
    await repo.updateAssessment(Assessment(
      id: existing.id,
      sessionId: existing.sessionId,
      type: existing.type,
      questions: existing.questions,
      startedAt: existing.startedAt,
      completedAt: DateTime.now().toIso8601String(),
      score: score,
    ));
  }

  Future<Assessment?> getById(String assessmentId) async {
    return repo.getAssessment(assessmentId);
  }

  static String _randomSuffix() {
    final rng = Random();
    return rng.nextInt(0xffffffff).toRadixString(16).padLeft(8, '0');
  }
}
